# Kubecost Module - Cost Monitoring for Kubernetes
# Provides per-pod, per-user, per-namespace cost tracking with AWS integration

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
    aws = {
      source  = "registry.opentofu.org/hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Create namespace for Kubecost
resource "kubernetes_namespace" "kubecost" {
  metadata {
    name = "kubecost"
    labels = {
      name = "kubecost"
    }
  }
}

# Service account for Kubecost (IRSA integration)
resource "kubernetes_service_account" "kubecost" {
  metadata {
    name      = "kubecost-cost-analyzer"
    namespace = kubernetes_namespace.kubecost.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = var.kubecost_irsa_role_arn
    }
  }
}

# Kubecost Helm Release
resource "helm_release" "kubecost" {
  name       = "kubecost"
  repository = "https://kubecost.github.io/cost-analyzer/"
  chart      = "cost-analyzer"
  version    = "1.108.1"  # Stable version compatible with free tier
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

      # Service account configuration (use pre-created with IRSA)
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

      # Ingress disabled (using LoadBalancer instead)
      ingress = {
        enabled = false
      }

      # Service configuration
      service = {
        type = var.expose_via_loadbalancer ? "LoadBalancer" : "ClusterIP"
        port = 9090
        annotations = var.expose_via_loadbalancer ? {
          "service.beta.kubernetes.io/aws-load-balancer-type" = "nlb"
          "service.beta.kubernetes.io/aws-load-balancer-scheme" = "internet-facing"
        } : {}
      }

      # Basic authentication (if enabled)
      # Note: This requires creating a secret with htpasswd
      # We'll handle this separately below
    })
  ]

  depends_on = [
    kubernetes_namespace.kubecost,
    kubernetes_service_account.kubecost
  ]
}

# ConfigMap for AWS credentials (if using static credentials instead of IRSA)
# Note: IRSA is preferred, this is a fallback
resource "kubernetes_secret" "aws_credentials" {
  count = var.use_irsa ? 0 : 1

  metadata {
    name      = "kubecost-aws-credentials"
    namespace = kubernetes_namespace.kubecost.metadata[0].name
  }

  data = {
    "aws-access-key-id"     = var.aws_access_key_id
    "aws-secret-access-key" = var.aws_secret_access_key
  }

  type = "Opaque"
}

# Basic auth secret for Kubecost UI (if enabled)
resource "kubernetes_secret" "kubecost_basic_auth" {
  count = var.kubecost_basic_auth_enabled ? 1 : 0

  metadata {
    name      = "kubecost-basic-auth"
    namespace = kubernetes_namespace.kubecost.metadata[0].name
  }

  data = {
    # htpasswd format: username:bcrypt_hash
    # Generate with: htpasswd -nB <username>
    # For now, using Apache MD5 which is weaker but works
    auth = "${var.kubecost_basic_auth_username}:${bcrypt(var.kubecost_basic_auth_password)}"
  }

  type = "Opaque"
}

# Nginx sidecar for basic auth (if enabled)
# This will be injected via Helm values as an additional container
# Kubernetes Ingress would be better, but we're using LoadBalancer for simplicity
