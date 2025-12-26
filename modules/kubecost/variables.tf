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
