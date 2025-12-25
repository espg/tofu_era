# Kubernetes module variables

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "s3_bucket" {
  description = "S3 bucket name for user data"
  type        = string
}

variable "kms_key_id" {
  description = "KMS key ID for encryption"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the OIDC provider for IRSA"
  type        = string
}
