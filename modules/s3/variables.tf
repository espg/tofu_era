variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "force_destroy" {
  description = "Allow destruction of bucket with contents"
  type        = bool
  default     = false
}

variable "lifecycle_days" {
  description = "Days to retain old versions (0 to disable)"
  type        = number
  default     = 7
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "region" {
  description = "AWS region for S3 buckets"
  type        = string
}

variable "enable_cur" {
  description = "Enable AWS Cost & Usage Report (CUR) for Kubecost"
  type        = bool
  default     = false
}

variable "cur_retention_days" {
  description = "Days to retain CUR data (0 to disable lifecycle policy)"
  type        = number
  default     = 90
}
