# Kubecost Module - Cost Monitoring for Kubernetes
# Uses Pod Identity for AWS authentication (not IRSA)
# Accessible via JupyterHub service proxy at /services/kubecost/
#
# Architecture:
# JupyterHub --> nginx-proxy (strips /services/kubecost prefix) --> Kubecost
#
# JupyterHub's CHP proxy does not strip path prefixes (GitHub Issue #3459)
# so we use an nginx proxy to handle the path rewriting.

terraform {
  required_providers {
    helm = {
      source  = "registry.opentofu.org/hashicorp/helm"
      version = "~> 2.12"
    }
    kubernetes = {
      source  = "registry.opentofu.org/hashicorp/kubernetes"
      version = "~> 2.24"
    }
  }
}

# Create namespace for Kubecost
resource "kubernetes_namespace" "kubecost" {
  metadata {
    name = "kubecost"
    labels = {
      name = "kubecost"
    }
  }
}

# Service account for Kubecost (Pod Identity handles IAM - no annotations needed)
resource "kubernetes_service_account" "kubecost" {
  metadata {
    name      = "kubecost-cost-analyzer"
    namespace = kubernetes_namespace.kubecost.metadata[0].name
    # No IRSA annotations - Pod Identity handles this via aws_eks_pod_identity_association
  }
}

# Kubecost Helm Release
resource "helm_release" "kubecost" {
  name       = "kubecost"
  repository = "https://kubecost.github.io/cost-analyzer/"
  chart      = "cost-analyzer"
  version    = "1.108.1" # Stable version compatible with free tier
  namespace  = kubernetes_namespace.kubecost.metadata[0].name

  # Wait for CRDs and pods to be ready
  wait             = true
  timeout          = 600
  create_namespace = false

  values = [
    yamlencode({
      # Global configuration
      global = {
        prometheus = {
          enabled = true
          fqdn    = "http://kubecost-prometheus-server.${kubernetes_namespace.kubecost.metadata[0].name}.svc"
        }
      }

      # Kubecost deployment configuration
      kubecostDeployment = {
        replicas = 1
      }

      # Kubecost model configuration
      kubecostModel = {
        warmCache        = true
        warmSavingsCache = true
        etl              = true
      }

      # Service account configuration (use pre-created - Pod Identity handles IAM)
      serviceAccount = {
        create = false
        name   = kubernetes_service_account.kubecost.metadata[0].name
      }

      # Node affinity - run on system nodes only
      nodeSelector = var.node_selector
      tolerations  = var.tolerations

      # Prometheus configuration (bundled with Kubecost)
      prometheus = {
        server = {
          persistentVolume = {
            enabled = true
            size    = "32Gi"
          }
          retention    = "15d"
          nodeSelector = var.node_selector
          tolerations  = var.tolerations
          resources = {
            requests = {
              cpu    = "500m"
              memory = "2Gi"
            }
            limits = {
              cpu    = "2000m"
              memory = "4Gi"
            }
          }
        }
        alertmanager = {
          enabled = false
        }
        pushgateway = {
          enabled = false
        }
        nodeExporter = {
          enabled = true
        }
        kubeStateMetrics = {
          enabled = true
        }
      }

      # Network costs
      networkCosts = {
        enabled = true
      }

      # Grafana disabled
      grafana = {
        enabled = false
      }

      # Ingress disabled - using JupyterHub service proxy instead
      ingress = {
        enabled = false
      }

      # Service configuration - ClusterIP for internal access only
      # JupyterHub proxies to this service at /services/kubecost/
      service = {
        type = "ClusterIP"
        port = 9090
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.kubecost,
    kubernetes_service_account.kubecost
  ]
}

# =============================================================================
# Nginx Reverse Proxy - Path Prefix Rewriting for JupyterHub Service Proxy
# =============================================================================
# JupyterHub's CHP proxy sends requests WITH the path prefix intact:
#   GET /services/kubecost/overview.html -> http://backend:9090/services/kubecost/overview.html
#
# Kubecost doesn't understand /services/kubecost/* paths, so nginx strips it:
#   /services/kubecost/overview.html -> /overview.html

# Nginx configuration for path rewriting
resource "kubernetes_config_map" "kubecost_proxy" {
  count = var.enable_jupyterhub_proxy ? 1 : 0

  metadata {
    name      = "kubecost-proxy-config"
    namespace = kubernetes_namespace.kubecost.metadata[0].name
  }

  data = {
    "nginx.conf" = <<-EOF
      events {
        worker_connections 1024;
      }

      http {
        upstream kubecost {
          server kubecost-cost-analyzer:9090;
        }

        server {
          listen 8080;

          # Strip /services/kubecost prefix and proxy to Kubecost
          # Handles both /services/kubecost and /services/kubecost/...
          location /services/kubecost {
            rewrite ^/services/kubecost/?(.*)$ /$1 break;
            proxy_pass http://kubecost;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;

            # WebSocket support for live updates
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";

            # Timeouts for long-running requests
            proxy_connect_timeout 60s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
          }

          # Health check endpoint
          location /healthz {
            return 200 "OK\n";
            add_header Content-Type text/plain;
          }
        }
      }
    EOF
  }
}

# Nginx deployment for path rewriting
resource "kubernetes_deployment" "kubecost_proxy" {
  count = var.enable_jupyterhub_proxy ? 1 : 0

  metadata {
    name      = "kubecost-proxy"
    namespace = kubernetes_namespace.kubecost.metadata[0].name
    labels = {
      app = "kubecost-proxy"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "kubecost-proxy"
      }
    }

    template {
      metadata {
        labels = {
          app = "kubecost-proxy"
        }
      }

      spec {
        # Run on system nodes (same as Kubecost)
        node_selector = var.node_selector

        container {
          name  = "nginx"
          image = "nginx:1.25-alpine"

          port {
            container_port = 8080
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/nginx/nginx.conf"
            sub_path   = "nginx.conf"
          }

          resources {
            requests = {
              cpu    = "10m"
              memory = "16Mi"
            }
            limits = {
              cpu    = "100m"
              memory = "64Mi"
            }
          }

          liveness_probe {
            http_get {
              path = "/healthz"
              port = 8080
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/healthz"
              port = 8080
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.kubecost_proxy[0].metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [helm_release.kubecost]
}

# Service for the nginx proxy - JupyterHub connects to this
resource "kubernetes_service" "kubecost_proxy" {
  count = var.enable_jupyterhub_proxy ? 1 : 0

  metadata {
    name      = "kubecost-proxy"
    namespace = kubernetes_namespace.kubecost.metadata[0].name
  }

  spec {
    selector = {
      app = "kubecost-proxy"
    }

    port {
      port        = 9090 # Same port as Kubecost for consistency
      target_port = 8080
    }

    type = "ClusterIP"
  }

  depends_on = [kubernetes_deployment.kubecost_proxy]
}
