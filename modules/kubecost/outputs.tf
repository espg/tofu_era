# Kubecost Module - Outputs

output "namespace" {
  description = "Kubernetes namespace where Kubecost is deployed"
  value       = kubernetes_namespace.kubecost.metadata[0].name
}

output "service_name" {
  description = "Kubernetes service name for Kubecost UI"
  value       = "kubecost-cost-analyzer"
}

output "service_port" {
  description = "Port for accessing Kubecost UI"
  value       = 9090
}

output "jupyterhub_service_url" {
  description = "URL to access Kubecost via JupyterHub (after login)"
  value       = "/services/kubecost/"
}

output "port_forward_command" {
  description = "kubectl command to access Kubecost UI directly (alternative)"
  value       = "kubectl port-forward -n kubecost svc/kubecost-cost-analyzer 9090:9090"
}

output "service_account_name" {
  description = "Kubernetes service account name for Kubecost"
  value       = kubernetes_service_account.kubecost.metadata[0].name
}
