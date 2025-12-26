# Terra JupyterHub - Variable Definitions

# Core Configuration
variable "environment" {
  description = "Environment name (cae, cae-dev, cae-testing)"
  type        = string
  validation {
    condition     = contains(["cae", "cae-dev", "cae-testing"], var.environment)
    error_message = "Environment must be cae, cae-dev, or cae-testing."
  }
}

variable "region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-west-2"
}

variable "cluster_name" {
  description = "Base name for the EKS cluster"
  type        = string
  default     = "jupyterhub"
}

variable "domain_name" {
  description = "Domain name for JupyterHub access"
  type        = string
}

# Deployment Type
variable "enable_jupyterhub" {
  description = "Enable JupyterHub deployment (set to false for standalone Dask Gateway only)"
  type        = bool
  default     = true
}

# ACM Certificate Configuration
variable "enable_acm" {
  description = "Enable ACM certificate creation (set to false for HTTP-only deployments)"
  type        = bool
  default     = true
}

variable "acm_enable_wildcard" {
  description = "Include wildcard (*.domain) as subject alternative name on ACM certificate"
  type        = bool
  default     = true
}

variable "acm_auto_validate" {
  description = "Automatically wait for ACM certificate DNS validation. Set to false for manual validation with external DNS providers."
  type        = bool
  default     = false
}

variable "acm_validation_timeout" {
  description = "Timeout for ACM certificate validation (only applies if acm_auto_validate is true)"
  type        = string
  default     = "45m"
}

variable "admin_email" {
  description = "Admin email for JupyterHub"
  type        = string
}

variable "owner_email" {
  description = "Owner email for tagging"
  type        = string
}

variable "cost_center" {
  description = "Cost center for tagging"
  type        = string
  default     = "engineering"
}

# Kubernetes Configuration
variable "kubernetes_version" {
  description = "Kubernetes version for EKS"
  type        = string
  default     = "1.29"
}

# Network Configuration
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnets (costs ~$45/month)"
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Use a single NAT Gateway to save costs"
  type        = bool
  default     = true
}

variable "pin_main_nodes_single_az" {
  description = "Pin main node group to single AZ (us-west-2a) for reliable scale-up with EBS volumes (test envs only)"
  type        = bool
  default     = false
}

variable "pin_user_nodes_single_az" {
  description = "Pin user node group to single AZ (us-west-2a) to fix PVC zone affinity for user persistent volumes"
  type        = bool
  default     = false
}

# Node Group Configuration - System (Always Running)
# For environments using 3-node-group architecture (system, user, worker)
variable "system_node_instance_types" {
  description = "Instance types for system node group (Hub, Kubecost, Prometheus)"
  type        = list(string)
  default     = ["r5.large"]
}

variable "system_node_min_size" {
  description = "Minimum number of system nodes (should be 1)"
  type        = number
  default     = 1
}

variable "system_node_desired_size" {
  description = "Desired number of system nodes (should be 1)"
  type        = number
  default     = 1
}

variable "system_node_max_size" {
  description = "Maximum number of system nodes (should be 1)"
  type        = number
  default     = 1
}

variable "system_enable_spot_instances" {
  description = "Use spot instances for system node group (NOT recommended)"
  type        = bool
  default     = false
}

# Node Group Configuration - User Pods (Scale to Zero)
# For environments using 3-node-group architecture
variable "user_node_instance_types" {
  description = "Instance types for user node group (JupyterHub user pods)"
  type        = list(string)
  default     = ["r5.xlarge"]
}

variable "user_node_min_size" {
  description = "Minimum number of user nodes (can be 0 for scale-to-zero)"
  type        = number
  default     = 0
}

variable "user_node_desired_size" {
  description = "Desired number of user nodes"
  type        = number
  default     = 0
}

variable "user_node_max_size" {
  description = "Maximum number of user nodes"
  type        = number
  default     = 10
}

variable "user_enable_spot_instances" {
  description = "Use spot instances for user node group (not recommended for user experience)"
  type        = bool
  default     = false
}

# User Node Scheduled Scaling
variable "enable_user_node_scheduling" {
  description = "Enable scheduled scaling for user node groups (scale up during business hours)"
  type        = bool
  default     = false
}

variable "user_node_schedule_timezone" {
  description = "Timezone for user node scheduling (e.g., America/Los_Angeles for Pacific)"
  type        = string
  default     = "America/Los_Angeles"
}

variable "user_node_schedule_scale_up_cron" {
  description = "Cron expression for scaling up user nodes (default: 8am Mon-Fri)"
  type        = string
  default     = "0 8 * * MON-FRI"
}

variable "user_node_schedule_scale_down_cron" {
  description = "Cron expression for scaling down user nodes (default: 5pm Mon-Fri)"
  type        = string
  default     = "0 17 * * MON-FRI"
}

variable "user_node_schedule_min_size_during_hours" {
  description = "Minimum user nodes during business hours"
  type        = number
  default     = 1
}

variable "user_node_schedule_min_size_after_hours" {
  description = "Minimum user nodes after hours (typically 0)"
  type        = number
  default     = 0
}

# Node Group Configuration - Main (Legacy/2-node architecture)
# Kept for backwards compatibility with existing environments
variable "main_node_instance_types" {
  description = "Instance types for main node group (legacy 2-node architecture)"
  type        = list(string)
  default     = ["r5.xlarge"]
}

variable "main_node_min_size" {
  description = "Minimum number of main nodes"
  type        = number
  default     = 1
}

variable "main_node_desired_size" {
  description = "Desired number of main nodes"
  type        = number
  default     = 1
}

variable "main_node_max_size" {
  description = "Maximum number of main nodes"
  type        = number
  default     = 5
}

variable "main_enable_spot_instances" {
  description = "Use spot instances for main node group (NOT recommended - causes JupyterHub instability)"
  type        = bool
  default     = false
}

# Node Group Configuration - Dask Workers
variable "dask_node_instance_types" {
  description = "Instance types for Dask worker nodes"
  type        = list(string)
  default     = ["m5.large", "m5.xlarge", "m5.2xlarge"]
}

variable "dask_node_min_size" {
  description = "Minimum number of Dask nodes"
  type        = number
  default     = 0 # Scale to zero!
}

variable "dask_node_desired_size" {
  description = "Desired number of Dask nodes"
  type        = number
  default     = 0
}

variable "dask_node_max_size" {
  description = "Maximum number of Dask nodes"
  type        = number
  default     = 30
}

variable "dask_enable_spot_instances" {
  description = "Use spot instances for Dask worker node group (recommended for cost savings)"
  type        = bool
  default     = true
}

# Node Group Architecture Selection
variable "use_three_node_groups" {
  description = "Use 3-node-group architecture (system, user, worker) instead of 2-node (main, worker)"
  type        = bool
  default     = false
}

# JupyterLab Profile Selection
variable "enable_profile_selection" {
  description = "Enable user selection of JupyterLab instance size (Small/Medium profiles)"
  type        = bool
  default     = true
}

# Container Image Configuration
variable "singleuser_image_name" {
  description = "Docker image name for single user notebooks"
  type        = string
  default     = "pangeo/pangeo-notebook"
}

variable "singleuser_image_tag" {
  description = "Docker image tag for single user notebooks"
  type        = string
  default     = "2024.04.08" # Compatible with DaskHub 2024.1.1 (JupyterHub 4.0.2)
}

# User Resource Limits
variable "user_cpu_guarantee" {
  description = "CPU cores guaranteed per user"
  type        = number
  default     = 2
}

variable "user_cpu_limit" {
  description = "Maximum CPU cores per user"
  type        = number
  default     = 4
}

variable "user_memory_guarantee" {
  description = "Memory guaranteed per user (GB)"
  type        = string
  default     = "15G"
}

variable "user_memory_limit" {
  description = "Maximum memory per user (GB)"
  type        = string
  default     = "30G"
}

# Dask Configuration
variable "dask_worker_cores_max" {
  description = "Maximum cores per Dask worker"
  type        = number
  default     = 4
}

variable "dask_worker_memory_max" {
  description = "Maximum memory per Dask worker (GB)"
  type        = number
  default     = 16
}

variable "dask_cluster_max_cores" {
  description = "Maximum total cores per Dask cluster"
  type        = number
  default     = 20
}

# Idle Timeouts
variable "kernel_cull_timeout" {
  description = "Timeout for idle kernels (seconds)"
  type        = number
  default     = 1200 # 20 minutes
}

variable "server_cull_timeout" {
  description = "Timeout for idle servers (seconds)"
  type        = number
  default     = 3600 # 1 hour
}

variable "dask_idle_timeout" {
  description = "Timeout for idle Dask clusters (seconds)"
  type        = number
  default     = 1800 # 30 minutes
}

# S3 Configuration
variable "s3_lifecycle_days" {
  description = "Days before S3 objects are deleted"
  type        = number
  default     = 30
}

variable "force_destroy_s3" {
  description = "Allow destroying S3 bucket with contents"
  type        = bool
  default     = false
}

# Cost Optimization
variable "scale_to_zero" {
  description = "Scale all nodes to zero (emergency cost savings)"
  type        = bool
  default     = false
}

variable "enable_auto_shutdown" {
  description = "Enable automatic shutdown on schedule"
  type        = bool
  default     = false
}

variable "shutdown_schedule" {
  description = "Cron schedule for automatic shutdown"
  type        = string
  default     = "0 19 * * MON-FRI" # 7 PM weekdays
}

variable "startup_schedule" {
  description = "Cron schedule for automatic startup"
  type        = string
  default     = "0 8 * * MON-FRI" # 8 AM weekdays
}

# Monitoring
variable "enable_monitoring" {
  description = "Enable CloudWatch monitoring and dashboards"
  type        = bool
  default     = false
}

variable "enable_kubecost" {
  description = "Enable Kubecost cost monitoring (accessible via JupyterHub at /services/kubecost/)"
  type        = bool
  default     = false
}

# GitHub OAuth Authentication
variable "github_enabled" {
  description = "Enable GitHub OAuth authentication"
  type        = bool
  default     = false
}

variable "github_org_whitelist" {
  description = "GitHub organization name to restrict access (leave empty for no restriction)"
  type        = string
  default     = ""
}

# Backup Configuration
variable "enable_backups" {
  description = "Enable automated EBS snapshots"
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Days to retain backups"
  type        = number
  default     = 7
}

# Destroy Protection
variable "deletion_protection" {
  description = "Prevent accidental deletion of critical resources"
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot when destroying RDS (if used)"
  type        = bool
  default     = false
}

# External Cognito Configuration (use existing user pool instead of creating new)
variable "use_external_cognito" {
  description = "Use an existing Cognito user pool instead of creating a new one"
  type        = bool
  default     = false
}

variable "external_cognito_client_id" {
  description = "Client ID for external Cognito user pool"
  type        = string
  default     = ""
}

variable "external_cognito_domain" {
  description = "Domain for external Cognito user pool (e.g., cae.auth.us-west-1.amazoncognito.com)"
  type        = string
  default     = ""
}

# Lifecycle Hooks Configuration
variable "lifecycle_hooks_enabled" {
  description = "Enable lifecycle hooks for custom package installation at pod startup"
  type        = bool
  default     = false
}

variable "lifecycle_post_start_command" {
  description = "Command to run after container starts (shell command as list)"
  type        = list(string)
  default     = ["sh", "-c", "echo 'No post-start hook configured'"]
}

# Existing S3 Bucket Configuration
variable "use_existing_s3_bucket" {
  description = "Use an existing S3 bucket instead of creating a new one"
  type        = bool
  default     = false
}

variable "existing_s3_bucket_name" {
  description = "Name of existing S3 bucket to use (only when use_existing_s3_bucket = true)"
  type        = string
  default     = ""
}

# Admin Users Configuration
variable "admin_users" {
  description = "List of admin user emails for JupyterHub"
  type        = list(string)
  default     = []
}

# Custom Image Selection
variable "enable_custom_image_selection" {
  description = "Allow users to specify custom Docker images at login (unlisted_choice)"
  type        = bool
  default     = false
}

variable "additional_image_choices" {
  description = "Additional Docker images available for selection at login"
  type = list(object({
    name         = string
    display_name = string
    description  = string
    default      = optional(bool, false)
  }))
  default = []
}

# VSCode Integration
variable "enable_vscode" {
  description = "Enable VSCode (code-server) access in JupyterLab via jupyter-vscode-proxy"
  type        = bool
  default     = false
}

variable "default_url" {
  description = "Default URL when user opens JupyterHub (e.g., /lab, /vscode, /tree)"
  type        = string
  default     = "/lab"
}