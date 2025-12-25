output "release_name" {
  description = "Name of the Helm release"
  value       = var.enable_jupyterhub ? helm_release.daskhub[0].name : helm_release.dask_gateway_standalone[0].name
}

output "release_namespace" {
  description = "Namespace of the Helm release"
  value       = var.enable_jupyterhub ? helm_release.daskhub[0].namespace : helm_release.dask_gateway_standalone[0].namespace
}

output "release_status" {
  description = "Status of the Helm release"
  value       = var.enable_jupyterhub ? helm_release.daskhub[0].status : helm_release.dask_gateway_standalone[0].status
}

output "gateway_token" {
  description = "API token for standalone Dask Gateway (only for standalone deployments)"
  value       = var.enable_jupyterhub ? null : random_password.gateway_token[0].result
  sensitive   = true
}

output "is_standalone_gateway" {
  description = "Whether this is a standalone Gateway deployment (no JupyterHub)"
  value       = !var.enable_jupyterhub
}
