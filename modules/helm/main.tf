# Helm Module - DaskHub or Standalone Dask Gateway Deployment
# Based on daskhub.yaml configuration

# Singleuser configuration - profile-based instance selection
locals {
  # Base role for node selection
  user_node_role = var.use_three_node_groups ? "user" : "main"

  # Build image choices for profile selection
  # Default image is always first
  default_image_choice = {
    "${var.singleuser_image_name}:${var.singleuser_image_tag}" = {
      display_name = "Default (${var.singleuser_image_tag})"
      default      = length(var.additional_image_choices) == 0 || !anytrue([for img in var.additional_image_choices : img.default])
      kubespawner_override = {
        image = "${var.singleuser_image_name}:${var.singleuser_image_tag}"
      }
    }
  }

  # Additional user-defined image choices
  additional_image_choices = {
    for img in var.additional_image_choices : img.name => {
      display_name = img.display_name
      description  = img.description
      default      = img.default
      kubespawner_override = {
        image = img.name
      }
    }
  }

  # Combined image choices
  image_choices = merge(local.default_image_choice, local.additional_image_choices)

  # Unlisted choice configuration for custom images
  unlisted_choice_config = var.enable_custom_image_selection ? {
    enabled                 = true
    display_name            = "Custom image"
    display_name_in_choices = "Specify a custom Docker image"
    description_in_choices  = "Use any publicly available Docker image (format: image:tag)"
    validation_regex        = "^.+:.+$"
    validation_message      = "Must be a valid Docker image with tag (e.g., pangeo/pangeo-notebook:2025.01.10)"
    kubespawner_override = {
      image = "{value}"
    }
  } : null

  # Profile-based configuration: users choose Small or Medium instance at login
  # When custom image selection is enabled, we add image selection within each profile
  singleuser_config = {
    serviceAccountName = var.user_service_account
    startTimeout       = 600
    defaultUrl         = var.default_url
    image = {
      name = var.singleuser_image_name
      tag  = var.singleuser_image_tag
    }
    extraEnv = {
      DASK_GATEWAY__ADDRESS                 = "http://proxy-public/services/dask-gateway"
      DASK_GATEWAY__CLUSTER__OPTIONS__IMAGE = "{{JUPYTER_IMAGE_SPEC}}"
      SCRATCH_BUCKET                        = "s3://${var.s3_bucket}/$(JUPYTERHUB_USER)"
    }
    lifecycleHooks = var.lifecycle_hooks_enabled ? {
      postStart = {
        exec = {
          command = var.lifecycle_post_start_command
        }
      }
    } : null
    extraFiles = {
      "jupyter_notebook_config.json" = {
        mountPath = "/etc/jupyter/jupyter_notebook_config.json"
        data = {
          MappingKernelManager = {
            cull_idle_timeout = var.kernel_cull_timeout
            cull_interval     = 120
            cull_connected    = true
            cull_busy         = false
          }
        }
      }
    }
    # Profile selection: Small (r5.large) or Medium (r5.xlarge)
    # When enable_custom_image_selection is true, each profile includes image selection
    # Note: r5.large has ~1930m allocatable CPU, minus ~230m for DaemonSets = ~1700m available
    # Uses "size" label to target separate node groups for reliable autoscaling
    profileList = var.enable_profile_selection ? [
      {
        display_name = "Small (2 CPU, 14 GB)"
        description  = "Standard JupyterLab environment"
        default      = true
        # Add image selection within this profile if enabled
        profile_options = var.enable_custom_image_selection || length(var.additional_image_choices) > 0 ? {
          image = {
            display_name    = "Image"
            unlisted_choice = local.unlisted_choice_config
            choices         = local.image_choices
          }
        } : null
        kubespawner_override = {
          cpu_guarantee = 1.6 # Must be < 1.7 to fit on r5.large after DaemonSet overhead
          cpu_limit     = 2
          mem_guarantee = "14G"
          mem_limit     = "15G"
          node_selector = {
            role = local.user_node_role
            size = "small" # Targets user-small node group (r5.large)
          }
        }
      },
      {
        display_name = "Medium (4 CPU, 28 GB)"
        description  = "For larger datasets and heavier computation"
        default      = false
        # Add image selection within this profile if enabled
        profile_options = var.enable_custom_image_selection || length(var.additional_image_choices) > 0 ? {
          image = {
            display_name    = "Image"
            unlisted_choice = local.unlisted_choice_config
            choices         = local.image_choices
          }
        } : null
        kubespawner_override = {
          cpu_guarantee = 3.5
          cpu_limit     = 4
          mem_guarantee = "28G"
          mem_limit     = "30G"
          node_selector = {
            role = local.user_node_role
            size = "medium" # Targets user-medium node group (r5.xlarge)
          }
        }
      }
    ] : null
    # Static resource config (used when enable_profile_selection = false)
    cpu = var.enable_profile_selection ? null : {
      limit     = var.user_cpu_limit
      guarantee = var.user_cpu_guarantee
    }
    memory = var.enable_profile_selection ? null : {
      limit     = var.user_memory_limit
      guarantee = var.user_memory_guarantee
    }
    nodeSelector = var.enable_profile_selection ? null : {
      role = local.user_node_role
    }
  }
}

# Full DaskHub (JupyterHub + Dask Gateway)
resource "helm_release" "daskhub" {
  count = var.enable_jupyterhub ? 1 : 0

  name             = "daskhub"
  repository       = "https://helm.dask.org"
  chart            = "daskhub"
  version          = "2024.1.1"
  namespace        = "daskhub"
  create_namespace = false # Namespace created by kubernetes module
  timeout          = 600

  # JupyterHub Configuration
  values = [
    yamlencode({
      jupyterhub = {
        # Singleuser config with profile selection (Small/Medium instance sizes)
        singleuser = local.singleuser_config
        proxy = {
          # Note: For NLB-terminated SSL, we do NOT enable JupyterHub's HTTPS
          # The NLB handles SSL termination, JupyterHub receives HTTP
          https = {
            enabled = false # NLB terminates SSL, not JupyterHub
          }
          service = {
            type = "LoadBalancer"
            # AWS Network Load Balancer (NLB) for proper WebSocket support
            # Classic ELB drops WebSocket connections due to HTTP mode and 60s idle timeout
            # NLB operates at Layer 4 (TCP) and properly maintains long-lived connections
            annotations = var.certificate_arn != "" ? {
              "service.beta.kubernetes.io/aws-load-balancer-type"            = "nlb"
              "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internet-facing"
              "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"
              "service.beta.kubernetes.io/aws-load-balancer-ssl-cert"        = var.certificate_arn
              "service.beta.kubernetes.io/aws-load-balancer-ssl-ports"       = "443"
              } : {
              "service.beta.kubernetes.io/aws-load-balancer-type"            = "nlb"
              "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internet-facing"
              "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"
            }
            # Expose both HTTP (80) and HTTPS (443) ports
            extraPorts = var.certificate_arn != "" ? [
              {
                name       = "https"
                port       = 443
                targetPort = "http" # Backend still uses HTTP, SSL terminates at NLB
              }
            ] : []
          }
          # Node affinity - proxy runs on system nodes (3-node) or main nodes (2-node)
          chp = {
            nodeSelector = {
              role = var.use_three_node_groups ? "system" : "main"
            }
            # No tolerations needed - system nodes don't have taints
          }
        }
        hub = {
          shutdownOnLogout = true
          # Node affinity - hub runs on system nodes (3-node) or main nodes (2-node)
          nodeSelector = {
            role = var.use_three_node_groups ? "system" : "main"
          }
          # No tolerations needed - system nodes don't have taints
          config = {
            Authenticator = {
              allow_all   = var.allow_all_users
              admin_users = var.admin_users
            }
            # KubeSpawner Configuration
            # Fix for terminal spawning issue - allowPrivilegeEscalation must be true for terminals to work
            # See: https://discourse.jupyter.org/t/singleuser-allowprivilegeescalation-not-work/14298
            KubeSpawner = {
              container_security_context = {
                runAsUser                = 1000
                runAsGroup               = 100
                allowPrivilegeEscalation = true # Required for JupyterLab terminals to function properly
              }
            }
            # GitHub OAuth Configuration
            GitHubOAuthenticator = var.github_enabled ? {
              client_id             = var.github_client_id
              client_secret         = var.github_client_secret
              oauth_callback_url    = var.certificate_arn != "" ? "https://${var.domain_name}/hub/oauth_callback" : "http://${var.domain_name}/hub/oauth_callback"
              allowed_organizations = var.github_org_whitelist != "" ? [var.github_org_whitelist] : []
              } : {
              client_id             = ""
              client_secret         = ""
              oauth_callback_url    = ""
              allowed_organizations = []
            }
            # Cognito OAuth Configuration (legacy)
            GenericOAuthenticator = var.cognito_enabled ? {
              client_id           = var.cognito_client_id
              oauth_callback_url  = "https://${var.domain_name}/hub/oauth_callback"
              authorize_url       = var.cognito_authorize_url
              token_url           = var.cognito_token_url
              userdata_url        = var.cognito_userdata_url
              logout_redirect_url = var.cognito_logout_url
              login_service       = "AWS Cognito"
              username_claim      = "email"
              } : {
              client_id           = ""
              oauth_callback_url  = ""
              authorize_url       = ""
              token_url           = ""
              userdata_url        = ""
              logout_redirect_url = ""
              login_service       = ""
              username_claim      = ""
            }
            JupyterHub = {
              authenticator_class = var.github_enabled ? "github" : (var.cognito_enabled ? "generic-oauth" : "dummy")
            }
          }
          # JupyterHub Service Proxy - Kubecost integration
          # Routes /services/kubecost/* to the kubecost-proxy nginx service
          # which strips the prefix before forwarding to Kubecost
          services = var.enable_kubecost_service ? {
            kubecost = {
              url     = "http://kubecost-proxy.kubecost.svc.cluster.local:9090"
              display = true
              admin   = false
            }
          } : {}
        }
      }
      # Dask Gateway Configuration
      "dask-gateway" = {
        gateway = {
          backend = {
            scheduler = {
              extraPodConfig = {
                serviceAccountName = "user-sa" # Use service account with S3 permissions
              }
            }
            worker = {
              extraPodConfig = {
                serviceAccountName = "user-sa" # Use service account with S3 permissions
                nodeSelector = {
                  "eks.amazonaws.com/capacityType" = "SPOT"
                }
                tolerations = [
                  {
                    key      = "lifecycle"
                    operator = "Equal"
                    value    = "spot"
                    effect   = "NoExecute"
                  }
                ]
              }
            }
          }
          extraConfig = {
            optionHandler = <<-EOF
              from dask_gateway_server.options import Options, Float, String, Mapping
              def cluster_options(user):
                  def option_handler(options):
                      if ":" not in options.image:
                          raise ValueError("When specifying an image you must also provide a tag")
                      extra_annotations = {"hub.jupyter.org/username": user.name.replace('@', '_')}
                      extra_labels = extra_annotations
                      return {
                          "worker_cores": 0.88 * min(options.worker_cores / 2, 1),
                          "worker_cores_limit": options.worker_cores,
                          "worker_memory": "%fG" % (0.88 * options.worker_memory),
                          "worker_memory_limit": "%fG" % options.worker_memory,
                          "image": options.image,
                          "environment": options.environment,
                          "extra_annotations": extra_annotations,
                          "extra_labels": extra_labels,
                      }
                  return Options(
                      Float("worker_cores", ${var.dask_worker_cores_max}, min=1, max=${var.dask_worker_cores_max}),
                      Float("worker_memory", ${var.dask_worker_memory_max}, min=1, max=${var.dask_worker_memory_max}),
                      String("image", default="${var.singleuser_image_name}:${var.singleuser_image_tag}"),
                      Mapping("environment", {}),
                      handler=option_handler,
                  )
              c.Backend.cluster_options = cluster_options
              c.ClusterConfig.idle_timeout = ${var.dask_idle_timeout}
              c.ClusterConfig.cluster_max_cores = ${var.dask_cluster_max_cores}
            EOF
          }
        }
      }
    })
  ]

  # Set client secret via set if Cognito enabled
  dynamic "set_sensitive" {
    for_each = var.cognito_enabled ? [1] : []
    content {
      name  = "jupyterhub.hub.config.GenericOAuthenticator.client_secret"
      value = var.cognito_client_secret
    }
  }
}

# Standalone Dask Gateway (no JupyterHub)
resource "helm_release" "dask_gateway_standalone" {
  count = var.enable_jupyterhub ? 0 : 1

  name             = "dask-gateway"
  repository       = "https://helm.dask.org"
  chart            = "dask-gateway"
  version          = "2024.1.0"
  namespace        = "daskhub" # Keep same namespace for consistency
  create_namespace = false
  timeout          = 600

  values = [
    yamlencode({
      gateway = {
        # Expose Gateway via LoadBalancer for external access
        service = {
          type = "LoadBalancer"
          annotations = {
            "service.beta.kubernetes.io/aws-load-balancer-type"   = "nlb"
            "service.beta.kubernetes.io/aws-load-balancer-scheme" = "internet-facing"
          }
        }
        # Authentication with API token
        auth = {
          type = "simple" # Simple token-based auth
          simple = {
            password = random_password.gateway_token[0].result
          }
        }
        backend = {
          scheduler = {
            extraPodConfig = {
              serviceAccountName = "user-sa"
              # Scheduler runs on main nodes (no taint needed for single node group)
            }
          }
          worker = {
            extraPodConfig = {
              serviceAccountName = "user-sa"
              # Schedule workers on spot instances
              nodeSelector = {
                "eks.amazonaws.com/capacityType" = "SPOT"
              }
              tolerations = [
                {
                  key      = "lifecycle"
                  operator = "Equal"
                  value    = "spot"
                  effect   = "NoExecute"
                }
              ]
            }
          }
        }
        extraConfig = {
          clusterConfig = <<-EOF
            from dask_gateway_server.options import Options, Float, String, Mapping

            def cluster_options(user):
                def option_handler(options):
                    if ":" not in options.image:
                        raise ValueError("When specifying an image you must also provide a tag")
                    return {
                        "worker_cores": 0.88 * options.worker_cores,
                        "worker_cores_limit": options.worker_cores,
                        "worker_memory": "%fG" % (0.88 * options.worker_memory),
                        "worker_memory_limit": "%fG" % options.worker_memory,
                        "image": options.image,
                        "environment": options.environment,
                    }
                return Options(
                    Float("worker_cores", ${var.dask_worker_cores_max}, min=1, max=${var.dask_worker_cores_max}),
                    Float("worker_memory", ${var.dask_worker_memory_max}, min=1, max=${var.dask_worker_memory_max}),
                    String("image", default="${var.singleuser_image_name}:${var.singleuser_image_tag}"),
                    Mapping("environment", {}),
                    handler=option_handler,
                )

            c.Backend.cluster_options = cluster_options
            c.ClusterConfig.idle_timeout = ${var.dask_idle_timeout}
            c.ClusterConfig.cluster_max_cores = ${var.dask_cluster_max_cores}
          EOF
        }
      }
    })
  ]
}

# Generate random API token for standalone Gateway
resource "random_password" "gateway_token" {
  count   = var.enable_jupyterhub ? 0 : 1
  length  = 32
  special = true
}

# Cluster Autoscaler
resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  version    = "9.37.0"
  namespace  = "kube-system"
  timeout    = 300

  values = [
    yamlencode({
      autoDiscovery = {
        clusterName = var.cluster_name
      }
      awsRegion = var.region
      rbac = {
        serviceAccount = {
          create = true
          name   = "cluster-autoscaler"
          annotations = {
            "eks.amazonaws.com/role-arn" = var.cluster_autoscaler_role_arn
          }
        }
      }
      extraArgs = {
        balance-similar-node-groups = true
        skip-nodes-with-system-pods = false
      }
    })
  ]
}
