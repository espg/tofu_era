# Terra JupyterHub - Development Environment Configuration

# Core Settings
environment  = "dev"
region      = "us-west-2"
cluster_name = "jupyterhub"
domain_name  = "jupyterhub-dev.example.com"
admin_email  = "admin@example.com"
owner_email  = "devops@example.com"
cost_center  = "engineering"

# Kubernetes
kubernetes_version = "1.29"

# Network Configuration - Cost Optimized for Dev
vpc_cidr           = "10.0.0.0/16"
enable_nat_gateway = false  # Save $45/month in dev - use public subnets
single_nat_gateway = true   # If enabled, use only one NAT

# Node Group - Main (Core Services)
main_node_instance_types = ["t3.large"]  # Cheaper for dev
main_node_min_size       = 0             # Can scale to zero
main_node_desired_size   = 1             # Start with 1
main_node_max_size       = 3             # Allow some scaling

# Node Group - Dask Workers
dask_node_instance_types = ["t3.medium", "t3.large"]  # Cheaper instances
dask_node_min_size       = 0                          # Always start at zero
dask_node_desired_size   = 0                          # No workers by default
dask_node_max_size       = 10                         # Limit for dev
enable_spot_instances    = true                       # Use spot for cost savings

# User Resource Limits - Reduced for Dev
user_cpu_guarantee    = 1      # 1 core guaranteed
user_cpu_limit       = 2      # 2 cores max
user_memory_guarantee = "4G"   # 4GB guaranteed
user_memory_limit    = "8G"   # 8GB max

# Dask Configuration - Reduced for Dev
dask_worker_cores_max  = 2    # Max 2 cores per worker
dask_worker_memory_max = 4    # Max 4GB per worker
dask_cluster_max_cores = 10   # Max 10 cores total per cluster

# Idle Timeouts - Aggressive for Dev
kernel_cull_timeout = 600   # 10 minutes
server_cull_timeout = 1800  # 30 minutes

# S3 Configuration
s3_lifecycle_days = 7       # Delete scratch data after 7 days in dev
force_destroy_s3  = true    # Allow destroying bucket with contents in dev

# Cost Optimization
scale_to_zero        = false  # Set to true for emergency cost savings
enable_auto_shutdown = true   # Auto shutdown in dev
shutdown_schedule    = "0 19 * * *"     # 7 PM every day
startup_schedule     = "0 8 * * MON-FRI" # 8 AM weekdays only

# Monitoring
enable_monitoring = false  # Disable monitoring in dev to save costs

# Backup Configuration
enable_backups        = false  # No backups in dev
backup_retention_days = 1      # Minimal retention if enabled

# Safety
deletion_protection = false  # Allow easy deletion in dev
skip_final_snapshot = true   # Don't create snapshots when destroying