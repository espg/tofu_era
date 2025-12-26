# CAE JupyterHub - Testing Environment
# Ephemeral testing environment with dummy auth
# Account: 992398409787

# Core Settings
environment  = "cae-testing"
region       = "us-west-2"
cluster_name = "jupyterhub-testing"
domain_name  = "" # No domain - use load balancer URL directly
admin_email  = "refuge@rocktalus.com"
owner_email  = "refuge@rocktalus.com"
cost_center  = "cae-testing"

# Admin Users (for dummy auth, any user can be admin)
admin_users = [
  "admin"
]

# EKS Cluster Access (aws-auth ConfigMap)
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

# ACM Certificate - Disabled (no domain)
enable_acm          = false
acm_enable_wildcard = false
acm_auto_validate   = false

# Network Configuration
vpc_cidr                   = "10.7.0.0/16" # Different CIDR from cae-dev
enable_nat_gateway         = true
single_nat_gateway         = true
pin_main_nodes_single_az   = true
pin_system_nodes_single_az = true
pin_user_nodes_single_az   = true

# Node Group Architecture - 3-node (system, user, dask)
use_three_node_groups = true

# Node Group - System (Always Running) - m5.large for adequate pod capacity
system_node_instance_types   = ["m5.large"]
system_node_min_size         = 1
system_node_desired_size     = 1
system_node_max_size         = 1
system_enable_spot_instances = false
system_node_disk_size        = 50

# Node Group - User - Minimal for testing
user_node_instance_types   = ["t3.large"]
user_node_min_size         = 0
user_node_desired_size     = 0
user_node_max_size         = 2
user_enable_spot_instances = false

# Disable scheduled scaling for testing
enable_user_node_scheduling = false

# Node Group - Dask Workers (Spot) - Limited for testing
dask_node_instance_types = [
  "t3.large",
  "m5.large"
]
dask_node_min_size         = 0
dask_node_desired_size     = 0
dask_node_max_size         = 5
dask_enable_spot_instances = true

# JupyterLab Profile Selection
enable_profile_selection = true

# User Resource Limits (fallback)
user_cpu_guarantee    = 1
user_cpu_limit        = 2
user_memory_guarantee = "4G"
user_memory_limit     = "8G"

# Dask Worker Configuration
dask_worker_cores_max  = 2
dask_worker_memory_max = 8
dask_cluster_max_cores = 10

# Container Image
# Custom CAE image based on py-rocket-base with:
# - VSCode (code-server), RStudio, Desktop from py-rocket-base
# - Dedicated "cae" conda environment with full pangeo stack + climakitae
# - "cae" kernel set as default for new notebooks
# See: docker/Dockerfile.cae and docs/CONTAINER_REGISTRY.md
singleuser_image_name = "ghcr.io/espg/cae-notebook"
singleuser_image_tag  = "latest"

# Lifecycle Hooks - DISABLED (all dependencies baked into image)
# The cae kernel includes climakitae, boto3, and full pangeo stack
lifecycle_hooks_enabled      = false
lifecycle_post_start_command = ["sh", "-c", "echo 'Dependencies pre-installed in cae kernel'"]

# Idle Timeouts - Very aggressive for testing
kernel_cull_timeout = 300 # 5 minutes
server_cull_timeout = 600 # 10 minutes
dask_idle_timeout   = 600 # 10 minutes

# S3 Configuration
use_existing_s3_bucket  = false
existing_s3_bucket_name = ""
s3_lifecycle_days       = 1
force_destroy_s3        = true

# Authentication - DUMMY AUTH (no login required)
github_enabled             = false
github_org_whitelist       = ""
use_external_cognito       = false
external_cognito_client_id = ""
external_cognito_domain    = ""

# Cost Optimization - Minimal for testing
scale_to_zero        = false
enable_auto_shutdown = false
enable_monitoring    = false
enable_kubecost      = false

# Safety - Testing settings (easy cleanup)
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

# Image pre-puller - now only pulls default image (not all profile images)
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
