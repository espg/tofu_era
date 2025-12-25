# EKS Module - Variables

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the cluster"
  type        = string
  default     = "1.29"
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where cluster will be deployed"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for the cluster and dask worker nodes"
  type        = list(string)
}

variable "main_node_subnet_ids" {
  description = "Subnet IDs for main node group (optionally single AZ for EBS volume affinity)"
  type        = list(string)
  default     = null
}

variable "kms_key_id" {
  description = "KMS key ID for encryption"
  type        = string
}

# Main Node Group
variable "main_node_instance_types" {
  description = "Instance types for main node group"
  type        = list(string)
}

variable "main_node_min_size" {
  description = "Minimum size of main node group"
  type        = number
}

variable "main_node_desired_size" {
  description = "Desired size of main node group"
  type        = number
}

variable "main_node_max_size" {
  description = "Maximum size of main node group"
  type        = number
}

# Dask Worker Node Group
variable "dask_node_instance_types" {
  description = "Instance types for Dask worker nodes"
  type        = list(string)
}

variable "dask_node_min_size" {
  description = "Minimum size of Dask node group"
  type        = number
}

variable "dask_node_desired_size" {
  description = "Desired size of Dask node group"
  type        = number
}

variable "dask_node_max_size" {
  description = "Maximum size of Dask node group"
  type        = number
}

variable "main_enable_spot_instances" {
  description = "Use spot instances for main node group (NOT recommended - causes JupyterHub instability)"
  type        = bool
  default     = false
}

variable "dask_enable_spot_instances" {
  description = "Use spot instances for Dask worker node group (recommended for cost savings)"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

# 3-Node-Group Architecture Variables
variable "use_three_node_groups" {
  description = "Use 3-node-group architecture (system, user, worker)"
  type        = bool
  default     = false
}

variable "system_node_instance_types" {
  description = "Instance types for system node group"
  type        = list(string)
  default     = ["r5.large"]
}

variable "system_node_min_size" {
  description = "Minimum size of system node group"
  type        = number
  default     = 1
}

variable "system_node_desired_size" {
  description = "Desired size of system node group"
  type        = number
  default     = 1
}

variable "system_node_max_size" {
  description = "Maximum size of system node group"
  type        = number
  default     = 1
}

variable "system_enable_spot_instances" {
  description = "Use spot instances for system node group"
  type        = bool
  default     = false
}

variable "user_node_instance_types" {
  description = "Instance types for user node group"
  type        = list(string)
  default     = ["r5.xlarge"]
}

variable "user_node_subnet_ids" {
  description = "Subnet IDs for user node group (optionally single AZ for EBS volume affinity). If null, uses subnet_ids."
  type        = list(string)
  default     = null
}

variable "user_node_min_size" {
  description = "Minimum size of user node group"
  type        = number
  default     = 0
}

variable "user_node_desired_size" {
  description = "Desired size of user node group"
  type        = number
  default     = 0
}

variable "user_node_max_size" {
  description = "Maximum size of user node group"
  type        = number
  default     = 10
}

variable "user_enable_spot_instances" {
  description = "Use spot instances for user node group"
  type        = bool
  default     = false
}