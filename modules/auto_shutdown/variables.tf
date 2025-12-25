# Variables for auto_shutdown

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "environment" {
  description = "Environment name (test, prod, etc.)"
  type        = string
}

variable "shutdown_schedule" {
  description = "Cron expression for shutdown schedule"
  type        = string
}

variable "startup_schedule" {
  description = "Cron expression for startup schedule"
  type        = string
}

variable "tags" {
  description = "Tags to apply to auto-shutdown resources"
  type        = map(string)
  default     = {}
}
