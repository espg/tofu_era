# Kubecost Module - Variables

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "cur_bucket_name" {
  description = "S3 bucket name for AWS Cost & Usage Reports"
  type        = string
}

variable "cur_prefix" {
  description = "Prefix for CUR data in S3 bucket"
  type        = string
  default     = "cur"
}

variable "kubecost_token" {
  description = "Kubecost product key (leave empty for free tier)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "kubecost_irsa_role_arn" {
  description = "IAM role ARN for Kubecost service account (IRSA)"
  type        = string
}

variable "use_irsa" {
  description = "Use IRSA for AWS authentication instead of static credentials"
  type        = bool
  default     = true
}

variable "aws_access_key_id" {
  description = "AWS access key ID (only if use_irsa = false)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "aws_secret_access_key" {
  description = "AWS secret access key (only if use_irsa = false)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "node_selector" {
  description = "Node selector for Kubecost pods"
  type        = map(string)
  default = {
    role = "system"
  }
}

variable "tolerations" {
  description = "Tolerations for Kubecost pods (not needed - system nodes have no taints)"
  type = list(object({
    key      = string
    operator = string
    value    = string
    effect   = string
  }))
  default = []
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "expose_via_loadbalancer" {
  description = "Expose Kubecost UI via LoadBalancer (vs ClusterIP requiring port-forward)"
  type        = bool
  default     = false
}

variable "kubecost_basic_auth_enabled" {
  description = "Enable basic authentication for Kubecost UI"
  type        = bool
  default     = false
}

variable "kubecost_basic_auth_username" {
  description = "Basic auth username for Kubecost UI"
  type        = string
  default     = "admin"
}

variable "kubecost_basic_auth_password" {
  description = "Basic auth password for Kubecost UI"
  type        = string
  default     = ""
  sensitive   = true
}
