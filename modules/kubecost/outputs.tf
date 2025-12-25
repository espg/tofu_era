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

output "port_forward_command" {
  description = "kubectl command to access Kubecost UI"
  value       = "kubectl port-forward -n kubecost svc/kubecost-cost-analyzer 9090:9090"
}

output "ui_url" {
  description = "URL to access Kubecost UI"
  value       = var.expose_via_loadbalancer ? "Check 'loadbalancer_hostname' output for public URL" : "http://localhost:9090 (use port-forward)"
}

output "loadbalancer_hostname" {
  description = "LoadBalancer hostname for Kubecost (if exposed publicly)"
  value       = var.expose_via_loadbalancer ? "Run: kubectl get svc -n kubecost kubecost-cost-analyzer -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'" : "Not exposed via LoadBalancer"
}

output "service_account_name" {
  description = "Kubernetes service account name for Kubecost"
  value       = kubernetes_service_account.kubecost.metadata[0].name
}
