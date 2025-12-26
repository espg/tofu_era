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

# Admin Users
admin_users = [
  "refuge@rocktalus.com"
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
pin_main_nodes_single_az = true # All nodes in single AZ (matches cae)
pin_user_nodes_single_az = true

# Node Group Architecture - 3-node (system, user, dask)
use_three_node_groups = true

# Node Group - System (Always Running) - Smaller for dev
system_node_instance_types   = ["t3.large"] # Cheaper for dev
system_node_min_size         = 1
system_node_desired_size     = 1
system_node_max_size         = 1
system_enable_spot_instances = false

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

# Container Image - Match production
singleuser_image_name = "pangeo/pangeo-notebook"
singleuser_image_tag  = "2025.01.10"

# Lifecycle Hooks - Test climakitae installation
lifecycle_hooks_enabled = true
lifecycle_post_start_command = [
  "sh", "-c",
  "/srv/conda/envs/notebook/bin/pip install --no-deps -e git+https://github.com/cal-adapt/climakitae.git#egg=climakitae -e git+https://github.com/cal-adapt/climakitaegui.git#egg=climakitaegui; /srv/conda/envs/notebook/bin/gitpuller https://github.com/cal-adapt/cae-notebooks main cae-notebooks || true"
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
