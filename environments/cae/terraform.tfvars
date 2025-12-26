# CAE JupyterHub - Production Environment Configuration
# Migrated from cae-jupyterhub (eksctl + Helm) to OpenTofu
#
# Key differences from old deployment:
# - 3-node architecture (system, user, dask) instead of 2-node
# - NLB instead of Classic ELB for WebSocket support
# - Profile selection (Small/Medium) at login
# - Scale-to-zero for user and worker nodes

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

# Kubernetes
kubernetes_version = "1.31"

# ACM Certificate
enable_acm          = true
acm_enable_wildcard = true  # *.cal-adapt.org
acm_auto_validate   = false # Manual DNS validation

# Network Configuration
vpc_cidr                 = "10.5.0.0/16" # Different from englacial's 10.4.0.0/16
enable_nat_gateway       = true
single_nat_gateway       = true # Single NAT to save costs
pin_main_nodes_single_az = true # All nodes in single AZ (matches cae-jupyterhub)
pin_user_nodes_single_az = true # Fix PVC zone affinity

# Node Group Architecture - 3-node (system, user, dask)
use_three_node_groups = true

# Node Group - System (Always Running)
system_node_instance_types   = ["r5.large"]
system_node_min_size         = 1
system_node_desired_size     = 1
system_node_max_size         = 1
system_enable_spot_instances = false

# Node Group - User (Scheduled Scaling)
# During business hours: min 1 node ready for fast login
# After hours: scales to zero to save costs
user_node_instance_types   = ["r5.large", "r5.xlarge"]
user_node_min_size         = 0
user_node_desired_size     = 0
user_node_max_size         = 30 # Match current CAE capacity
user_enable_spot_instances = false

# User Node Scheduled Scaling - warm node during business hours
enable_user_node_scheduling              = true
user_node_schedule_timezone              = "America/Los_Angeles" # Pacific Time
user_node_schedule_scale_up_cron         = "0 8 * * MON-FRI"     # 8am PT Mon-Fri
user_node_schedule_scale_down_cron       = "0 17 * * MON-FRI"    # 5pm PT Mon-Fri
user_node_schedule_min_size_during_hours = 1                     # Keep 1 node warm
user_node_schedule_min_size_after_hours  = 0                     # Scale to zero

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
dask_node_max_size         = 30 # Match current CAE capacity
dask_enable_spot_instances = true

# JupyterLab Profile Selection - Users choose instance size at login
enable_profile_selection = true

# User Resource Limits (fallback when profile selection disabled)
user_cpu_guarantee    = 2
user_cpu_limit        = 4
user_memory_guarantee = "15G"
user_memory_limit     = "30G"

# Dask Worker Configuration - FLEXIBLE (matching current CAE)
dask_worker_cores_max  = 4  # Users can choose 1-4 cores per worker
dask_worker_memory_max = 16 # Users can choose up to 16GB per worker
dask_cluster_max_cores = 20 # Max 20 cores per cluster

# Dask Cluster Timeout - Match current CAE (30 minutes)
dask_idle_timeout = 1800 # 30 minutes (matches cae-jupyterhub)

# Container Image - Match current CAE
singleuser_image_name = "pangeo/pangeo-notebook"
singleuser_image_tag  = "2025.01.10"

# Lifecycle Hooks - climakitae installation
lifecycle_hooks_enabled = true
lifecycle_post_start_command = [
  "sh", "-c",
  "/srv/conda/envs/notebook/bin/pip install --no-deps -e git+https://github.com/cal-adapt/climakitae.git#egg=climakitae -e git+https://github.com/cal-adapt/climakitaegui.git#egg=climakitaegui; /srv/conda/envs/notebook/bin/gitpuller https://github.com/cal-adapt/cae-notebooks main cae-notebooks || true"
]

# Idle Timeouts - Match current CAE
kernel_cull_timeout = 1200 # 20 minutes
server_cull_timeout = 3600 # 60 minutes

# S3 Configuration - USE EXISTING BUCKET
use_existing_s3_bucket  = true
existing_s3_bucket_name = "cadcat-tmp"
s3_lifecycle_days       = 30
force_destroy_s3        = false

# Authentication - EXTERNAL COGNITO (existing user pool in us-west-1)
github_enabled             = false
use_external_cognito       = true
external_cognito_client_id = "3jesa7vt6hanjscanmj93cj2kg"
external_cognito_domain    = "cae.auth.us-west-1.amazoncognito.com"

# Cost Optimization
scale_to_zero        = false
enable_auto_shutdown = false
enable_monitoring    = false
enable_kubecost      = true # Cost monitoring with AWS CUR integration

# Safety - Production settings
deletion_protection = true
skip_final_snapshot = false

# Backup Configuration
enable_backups        = true
backup_retention_days = 7
