variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "enable_jupyterhub" {
  description = "Enable JupyterHub deployment (false = standalone Dask Gateway only)"
  type        = bool
  default     = true
}

variable "domain_name" {
  description = "Domain name for JupyterHub"
  type        = string
}

variable "certificate_arn" {
  description = "ARN of ACM certificate for HTTPS"
  type        = string
  default     = ""
}

variable "s3_bucket" {
  description = "S3 bucket name for user scratch data"
  type        = string
  default     = ""
}

variable "cognito_domain" {
  description = "Cognito domain"
  type        = string
  default     = ""
}

variable "cognito_user_pool_id" {
  description = "Cognito user pool ID"
  type        = string
  default     = ""
}

variable "admin_email" {
  description = "Admin email for JupyterHub"
  type        = string
  default     = ""
}

variable "user_service_account" {
  description = "Kubernetes service account for user pods"
  type        = string
  default     = "user-sa"
}

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

variable "user_cpu_guarantee" {
  description = "Guaranteed CPU cores for user pods"
  type        = number
}

variable "user_cpu_limit" {
  description = "Maximum CPU cores for user pods"
  type        = number
}

variable "user_memory_guarantee" {
  description = "Guaranteed memory for user pods"
  type        = string
}

variable "user_memory_limit" {
  description = "Maximum memory for user pods"
  type        = string
}

variable "dask_worker_cores_max" {
  description = "Maximum CPU cores per Dask worker"
  type        = number
}

variable "dask_worker_memory_max" {
  description = "Maximum memory per Dask worker (GB)"
  type        = number
}

variable "dask_cluster_max_cores" {
  description = "Maximum total cores per Dask cluster"
  type        = number
}

variable "kernel_cull_timeout" {
  description = "Idle timeout for Jupyter kernels (seconds)"
  type        = number
}

variable "server_cull_timeout" {
  description = "Idle timeout for user servers (seconds)"
  type        = number
}

variable "dask_idle_timeout" {
  description = "Idle timeout for Dask clusters (seconds)"
  type        = number
  default     = 1800 # 30 minutes
}

variable "admin_users" {
  description = "List of admin user emails"
  type        = list(string)
  default     = []
}

variable "allow_all_users" {
  description = "Allow all authenticated users to access hub"
  type        = bool
  default     = true
}

variable "cognito_enabled" {
  description = "Enable Cognito authentication"
  type        = bool
  default     = false
}

variable "cognito_client_id" {
  description = "Cognito app client ID"
  type        = string
  default     = ""
}

variable "cognito_client_secret" {
  description = "Cognito app client secret"
  type        = string
  default     = ""
  sensitive   = true
}

variable "cognito_authorize_url" {
  description = "Cognito OAuth authorize URL"
  type        = string
  default     = ""
}

variable "cognito_token_url" {
  description = "Cognito OAuth token URL"
  type        = string
  default     = ""
}

variable "cognito_userdata_url" {
  description = "Cognito OAuth userdata URL"
  type        = string
  default     = ""
}

variable "cognito_logout_url" {
  description = "Cognito logout redirect URL"
  type        = string
  default     = ""
}

variable "lifecycle_hooks_enabled" {
  description = "Enable lifecycle hooks for custom package installation"
  type        = bool
  default     = false
}

variable "lifecycle_post_start_command" {
  description = "Command to run after container starts"
  type        = list(string)
  default     = ["sh", "-c", "echo 'No post-start hook configured'"]
}

variable "region" {
  description = "AWS region for cluster autoscaler"
  type        = string
}

variable "cluster_autoscaler_role_arn" {
  description = "IAM role ARN for cluster autoscaler"
  type        = string
}

variable "use_three_node_groups" {
  description = "Use 3-node-group architecture (system, user, worker) vs 2-node (main, worker)"
  type        = bool
  default     = false
}

# JupyterLab Profile Selection
variable "enable_profile_selection" {
  description = "Enable user selection of JupyterLab instance size (Small/Medium profiles)"
  type        = bool
  default     = true
}

# GitHub OAuth Authentication
variable "github_enabled" {
  description = "Enable GitHub OAuth authentication"
  type        = bool
  default     = false
}

variable "github_client_id" {
  description = "GitHub OAuth app client ID"
  type        = string
  default     = ""
}

variable "github_client_secret" {
  description = "GitHub OAuth app client secret"
  type        = string
  default     = ""
  sensitive   = true
}

variable "github_org_whitelist" {
  description = "GitHub organization name to restrict access (optional)"
  type        = string
  default     = ""
}

# Kubecost integration via JupyterHub service proxy
variable "enable_kubecost_service" {
  description = "Enable Kubecost as a JupyterHub service (accessible at /services/kubecost after login)"
  type        = bool
  default     = false
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

# VSCode integration
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
