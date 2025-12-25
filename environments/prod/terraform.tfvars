# Terra JupyterHub - Production Environment Configuration

# Core Settings
environment  = "prod"
region      = "us-west-2"
cluster_name = "jupyterhub"
domain_name  = "jupyterhub.example.com"  # Production domain
admin_email  = "admin@example.com"
owner_email  = "platform@example.com"
cost_center  = "platform"

# Kubernetes
kubernetes_version = "1.29"

# Network Configuration - HA for Production
vpc_cidr           = "10.0.0.0/16"
enable_nat_gateway = true   # Required for private subnets
single_nat_gateway = false  # Multiple NATs for HA

# Node Group - Main (Core Services) - HA Configuration
main_node_instance_types = ["r5.xlarge", "r5a.xlarge"]  # Production instances
main_node_min_size       = 2                            # HA minimum
main_node_desired_size   = 2                            # HA setup
main_node_max_size       = 10                           # Allow scaling

# Node Group - Dask Workers - Production Scale
dask_node_instance_types = ["m5.large", "m5.xlarge", "m5.2xlarge", "m5.4xlarge"]
dask_node_min_size       = 0     # Still scale to zero when unused
dask_node_desired_size   = 0     # Start with zero
dask_node_max_size       = 50    # Higher limit for production
enable_spot_instances    = true  # Still use spot for workers

# User Resource Limits - Production
user_cpu_guarantee    = 2      # 2 cores guaranteed
user_cpu_limit       = 4      # 4 cores max
user_memory_guarantee = "15G"  # 15GB guaranteed
user_memory_limit    = "30G"  # 30GB max

# Dask Configuration - Production
dask_worker_cores_max  = 4    # 4 cores per worker
dask_worker_memory_max = 16   # 16GB per worker
dask_cluster_max_cores = 40   # 40 cores total per cluster

# Idle Timeouts - Balanced for Production
kernel_cull_timeout = 1200  # 20 minutes
server_cull_timeout = 3600  # 1 hour

# S3 Configuration
s3_lifecycle_days = 30      # 30 days retention
force_destroy_s3  = false   # Protect against accidental deletion

# Cost Optimization
scale_to_zero        = false  # Never auto-scale to zero in prod
enable_auto_shutdown = false  # No auto shutdown in production

# Monitoring
enable_monitoring = true  # Enable full monitoring

# Backup Configuration
enable_backups        = true  # Enable backups
backup_retention_days = 30    # 30 days retention

# Safety
deletion_protection = true   # Prevent accidental deletion
skip_final_snapshot = false  # Always create snapshots