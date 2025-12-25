# Kubernetes module outputs

output "user_service_account_name" {
  description = "Name of the user service account"
  value       = kubernetes_service_account.user_sa.metadata[0].name
}

output "user_iam_role_arn" {
  description = "ARN of the IAM role for user service account"
  value       = module.user_s3_irsa.role_arn
}
