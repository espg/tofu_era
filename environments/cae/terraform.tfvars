# CAE JupyterHub - Production Environment Configuration
# Based on cae-dev with production-specific settings

# Core Settings
environment  = "cae"
region       = "us-west-2"
cluster_name = "jupyterhub"
domain_name  = "hub.cal-adapt.org"
admin_email  = "mark.koenig@eaglerockanalytics.com"
owner_email  = "devops@eaglerockanalytics.com"
cost_center  = "cae"

# Admin Users
admin_users = [
  "mark.koenig@eaglerockanalytics.com",
  "neil.schroeder@eaglerockanalytics.com"
]

# EKS Cluster Access
cluster_admin_roles = []
cluster_admin_users = []

# Kubernetes
kubernetes_version = "1.34"

# ACM Certificate
enable_acm          = true
acm_enable_wildcard = true  # *.cal-adapt.org
acm_auto_validate   = false # Manual DNS validation

# Network Configuration
vpc_cidr                   = "10.5.0.0/16"
enable_nat_gateway         = true
single_nat_gateway         = true
pin_main_nodes_single_az   = true
pin_system_nodes_single_az = true
pin_user_nodes_single_az   = true

# Node Group Architecture - 3-node (system, user, dask)
use_three_node_groups = true

# Node Group - System (Always Running)
system_node_instance_types   = ["r5.large"]
system_node_min_size         = 1
system_node_desired_size     = 1
system_node_max_size         = 1
system_enable_spot_instances = false
system_node_disk_size        = 50

# Node Group - User (Scheduled Scaling)
user_node_instance_types   = ["r5.large", "r5.xlarge"]
user_node_min_size         = 0
user_node_desired_size     = 0
user_node_max_size         = 30
user_enable_spot_instances = false

# User Node Scheduled Scaling - warm node during business hours
enable_user_node_scheduling              = true
user_node_schedule_timezone              = "America/Los_Angeles"
user_node_schedule_scale_up_cron         = "0 8 * * MON-FRI"
user_node_schedule_scale_down_cron       = "0 17 * * MON-FRI"
user_node_schedule_min_size_during_hours = 1
user_node_schedule_min_size_after_hours  = 0

# Node Group - Dask Workers (Spot)
dask_node_instance_types = [
  "m5.large",
  "m5.xlarge",
  "m5.2xlarge",
  "m5.4xlarge",
  "m5a.large",
  "m5a.xlarge",
  "m5a.2xlarge",
  "m5a.4xlarge"
]
dask_node_min_size         = 0
dask_node_desired_size     = 0
dask_node_max_size         = 30
dask_enable_spot_instances = true

# JupyterLab Profile Selection
enable_profile_selection = true

# User Resource Limits (fallback)
user_cpu_guarantee    = 2
user_cpu_limit        = 4
user_memory_guarantee = "15G"
user_memory_limit     = "30G"

# Dask Worker Configuration
dask_worker_cores_max  = 4
dask_worker_memory_max = 16
dask_cluster_max_cores = 20

# Container Image & Lifecycle Hooks: Uses defaults from variables.tf
# - ghcr.io/espg/cae-notebook:latest (CAE image with climakitae + pangeo stack)
# - Pulls cae-notebooks repo on startup via nbgitpuller

# Idle Timeouts - Production (less aggressive than dev)
kernel_cull_timeout = 1200 # 20 minutes
server_cull_timeout = 3600 # 60 minutes
dask_idle_timeout   = 1800 # 30 minutes

# S3 Configuration - USE EXISTING BUCKET
use_existing_s3_bucket  = true
existing_s3_bucket_name = "cadcat-tmp"
s3_lifecycle_days       = 30
force_destroy_s3        = false

# Authentication - EXTERNAL COGNITO (existing user pool in us-west-1)
github_enabled             = false
github_org_whitelist       = ""
use_external_cognito       = true
external_cognito_client_id = "3jesa7vt6hanjscanmj93cj2kg"
external_cognito_domain    = "cae.auth.us-west-1.amazoncognito.com"

# Cost Optimization
scale_to_zero        = false
enable_auto_shutdown = false # Production always available
enable_monitoring    = false
enable_kubecost      = true

# Safety - Production settings
deletion_protection = true
skip_final_snapshot = false

# Backup Configuration
enable_backups        = true
backup_retention_days = 7

# VSCode Integration
enable_vscode = true
default_url   = "/lab"

# Image pre-puller
enable_continuous_image_puller = true

# Custom Image Selection
enable_custom_image_selection = true

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
