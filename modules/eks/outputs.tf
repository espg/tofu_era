# EKS Module - Outputs

output "cluster_id" {
  description = "The name/id of the EKS cluster"
  value       = aws_eks_cluster.main.id
}

output "cluster_name" {
  description = "The name of the EKS cluster"
  value       = aws_eks_cluster.main.name
}

output "cluster_arn" {
  description = "The Amazon Resource Name (ARN) of the cluster"
  value       = aws_eks_cluster.main.arn
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_version" {
  description = "The Kubernetes server version for the cluster"
  value       = aws_eks_cluster.main.version
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

output "cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster OIDC Issuer"
  value       = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC Provider for IRSA"
  value       = aws_iam_openid_connect_provider.cluster.arn
}

output "cluster_iam_role_arn" {
  description = "IAM role ARN of the EKS cluster"
  value       = aws_iam_role.cluster.arn
}

output "node_iam_role_arn" {
  description = "IAM role ARN of the EKS nodes"
  value       = aws_iam_role.node.arn
}

output "main_node_group_id" {
  description = "EKS node group ID for main nodes (legacy 2-node architecture)"
  value       = try(aws_eks_node_group.main[0].id, null)
}

output "main_node_group_status" {
  description = "Status of the main node group (legacy 2-node architecture)"
  value       = try(aws_eks_node_group.main[0].status, null)
}

output "system_node_group_id" {
  description = "EKS node group ID for system nodes (3-node architecture)"
  value       = try(aws_eks_node_group.system[0].id, null)
}

output "system_node_group_status" {
  description = "Status of the system node group (3-node architecture)"
  value       = try(aws_eks_node_group.system[0].status, null)
}

output "user_small_node_group_id" {
  description = "EKS node group ID for user-small nodes (r5.large)"
  value       = try(aws_eks_node_group.user_small[0].id, null)
}

output "user_small_node_group_status" {
  description = "Status of the user-small node group"
  value       = try(aws_eks_node_group.user_small[0].status, null)
}

output "user_medium_node_group_id" {
  description = "EKS node group ID for user-medium nodes (r5.xlarge)"
  value       = try(aws_eks_node_group.user_medium[0].id, null)
}

output "user_medium_node_group_status" {
  description = "Status of the user-medium node group"
  value       = try(aws_eks_node_group.user_medium[0].status, null)
}

output "dask_node_group_id" {
  description = "EKS node group ID for Dask workers"
  value       = aws_eks_node_group.dask_workers.id
}

output "dask_node_group_status" {
  description = "Status of the Dask node group"
  value       = aws_eks_node_group.dask_workers.status
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = aws_security_group.cluster.id
}

output "kubectl_config_command" {
  description = "kubectl config command to connect to the cluster"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${aws_eks_cluster.main.name}"
}

output "cluster_autoscaler_arn" {
  description = "ARN of the cluster autoscaler IAM role"
  value       = module.cluster_autoscaler_irsa.role_arn
}