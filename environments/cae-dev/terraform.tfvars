# CAE JupyterHub - Development/Testing Environment
# Used to test the CAE migration before production deployment
# Account: 992398409787 (different from production)

# Core Settings
environment  = "cae-dev"
region       = "us-west-2"
cluster_name = "jupyterhub"
domain_name  = "cae-dev.rocktalus.com"
admin_email  = "refuge@rocktalus.com"
owner_email  = "refuge@rocktalus.com"
cost_center  = "cae-dev"

# Admin Users (JupyterHub)
admin_users = [
  "refuge@rocktalus.com"
]

# EKS Cluster Access (aws-auth ConfigMap)
# These IAM identities get cluster admin (system:masters) access
cluster_admin_roles = [
  {
    arn      = "arn:aws:iam::992398409787:role/github-actions-tofu-era"
    username = "github-actions"
  }
]

cluster_admin_users = [
  {
    arn      = "arn:aws:iam::992398409787:user/espg"
    username = "espg"
  }
]

# Kubernetes
kubernetes_version = "1.31"

# ACM Certificate - Manual DNS validation (no Route53)
enable_acm          = true
acm_enable_wildcard = false
acm_auto_validate   = false # Manually add DNS validation records

# Network Configuration
vpc_cidr                 = "10.6.0.0/16" # Different CIDR for dev
enable_nat_gateway       = true
single_nat_gateway       = true
pin_main_nodes_single_az   = true # All nodes in single AZ (matches cae)
pin_system_nodes_single_az = true # Prevents hub PVC/node zone affinity conflicts
pin_user_nodes_single_az   = true

# Node Group Architecture - 3-node (system, user, dask)
use_three_node_groups = true

# Node Group - System (Always Running) - Smaller for dev
system_node_instance_types   = ["t3.large"] # Cheaper for dev
system_node_min_size         = 1
system_node_desired_size     = 1
system_node_max_size         = 1
system_enable_spot_instances = false
system_node_disk_size        = 50

# Node Group - User (Scheduled Scaling) - Smaller for dev
user_node_instance_types   = ["t3.large", "t3.xlarge"]
user_node_min_size         = 0
user_node_desired_size     = 0
user_node_max_size         = 5
user_enable_spot_instances = false

# User Node Scheduled Scaling - warm node during business hours (same as production)
enable_user_node_scheduling              = true
user_node_schedule_timezone              = "America/Los_Angeles" # Pacific Time
user_node_schedule_scale_up_cron         = "0 8 * * MON-FRI"     # 8am PT Mon-Fri
user_node_schedule_scale_down_cron       = "0 17 * * MON-FRI"    # 5pm PT Mon-Fri
user_node_schedule_min_size_during_hours = 1                     # Keep 1 node warm
user_node_schedule_min_size_after_hours  = 0                     # Scale to zero

# Node Group - Dask Workers (Spot) - Limited for dev
dask_node_instance_types = [
  "t3.large",
  "t3.xlarge",
  "m5.large",
  "m5a.large"
]
dask_node_min_size         = 0
dask_node_desired_size     = 0
dask_node_max_size         = 10
dask_enable_spot_instances = true

# JupyterLab Profile Selection - Test profile selection
enable_profile_selection = true

# User Resource Limits (fallback)
user_cpu_guarantee    = 2
user_cpu_limit        = 4
user_memory_guarantee = "15G"
user_memory_limit     = "30G"

# Dask Worker Configuration - FLEXIBLE (same as production)
dask_worker_cores_max  = 4
dask_worker_memory_max = 16
dask_cluster_max_cores = 20

# Container Image - Custom CAE image with climakitae + pangeo stack + VSCode/RStudio
# Built from: docker/Dockerfile.cae (extends py-rocket-base)
# Includes: climakitae, climakitaegui, full pangeo stack, VSCode, RStudio, Desktop
singleuser_image_name = "ghcr.io/espg/cae-notebook"
singleuser_image_tag  = "latest"

# Lifecycle Hooks - Only pull CAE notebooks (climakitae already in image)
lifecycle_hooks_enabled = true
lifecycle_post_start_command = [
  "sh", "-c",
  "/srv/conda/envs/cae/bin/gitpuller https://github.com/cal-adapt/cae-notebooks main cae-notebooks || true"
]

# Idle Timeouts - Aggressive for dev
kernel_cull_timeout = 600  # 10 minutes
server_cull_timeout = 1800 # 30 minutes
dask_idle_timeout   = 1800 # 30 minutes (matches cae-jupyterhub and cae)

# S3 Configuration - CREATE NEW BUCKET (not existing)
use_existing_s3_bucket  = false
existing_s3_bucket_name = ""
s3_lifecycle_days       = 7 # Short retention for dev
force_destroy_s3        = true

# Authentication - Cognito (us-west-1)
github_enabled             = false
github_org_whitelist       = ""
use_external_cognito       = true
external_cognito_client_id = "4fumjktp49ajd8tvrf6glevbfr"
external_cognito_domain    = "cae-dev-hub.auth.us-west-1.amazoncognito.com"

# Cost Optimization
scale_to_zero        = false
enable_auto_shutdown = true
shutdown_schedule    = "0 20 * * *"      # 8 PM daily
startup_schedule     = "0 8 * * MON-FRI" # 8 AM weekdays
enable_monitoring    = false
enable_kubecost      = true # Cost monitoring (same as production)

# Safety - Dev settings (easy cleanup)
deletion_protection = false
skip_final_snapshot = true

# Backup Configuration
enable_backups        = false
backup_retention_days = 1

# VSCode Integration
# py-rocket-base includes code-server, so VSCode is available at /vscode
# Also includes RStudio at /rstudio and Desktop at /desktop
enable_vscode = true
default_url   = "/lab" # JupyterLab default; VSCode at /vscode, RStudio at /rstudio

# Image pre-puller - only pulls default image (not all profile images)
enable_continuous_image_puller = true

# Custom Image Selection
# Allow users to choose from multiple images or specify their own at login
enable_custom_image_selection = true

# Additional image options for users
# slug must be ≤63 chars, lowercase alphanumeric + dashes only
additional_image_choices = [
  {
    name         = "pangeo/pangeo-notebook:2025.01.10"
    slug         = "pangeo"
    display_name = "Pangeo Notebook (no VSCode)"
    description  = "Standard Pangeo stack - JupyterLab only, no VSCode/RStudio"
    default      = false
  },
  {
    name         = "jupyter/scipy-notebook:latest"
    slug         = "scipy"
    display_name = "SciPy Notebook (no VSCode)"
    description  = "Jupyter's official SciPy notebook - JupyterLab only"
    default      = false
  }
]
