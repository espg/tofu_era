# Kubecost Module - Cost Monitoring for Kubernetes
# Uses Pod Identity for AWS authentication (not IRSA)
# Accessible via JupyterHub service proxy at /services/kubecost/

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
