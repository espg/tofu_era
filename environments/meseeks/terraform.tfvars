# Terra JupyterHub - Meseeks Environment Configuration
# Standalone Dask Gateway cluster for external access from CryoCloud
# No JupyterHub - workers only with lightweight configuration

# Core Settings
environment  = "meseeks"
region      = "us-west-2"  # NASA NSIDC S3 data access region
cluster_name = "jupyterhub-meseeks"
domain_name  = "meseeks.example.com"  # Placeholder - Gateway accessed via LoadBalancer
admin_email  = "admin@example.com"
owner_email  = "devops@example.com"
cost_center  = "research"

# Kubernetes
kubernetes_version = "1.29"

# Deployment Type - STANDALONE DASK GATEWAY (no JupyterHub)
enable_jupyterhub = false  # Only deploy Dask Gateway
enable_acm        = false  # No SSL needed for Gateway API

# Network Configuration - Cost-Optimized
vpc_cidr           = "10.20.0.0/16"  # Unique CIDR for meseeks
enable_nat_gateway = true            # Need NAT for image pulls and API access
single_nat_gateway = true            # Single NAT to save $45/month

# Single Node Group - Workers + Gateway Scheduler
# Optimized for spot availability with diverse instance types
# Target: 1 CPU / 3GB RAM per worker, ~2-4 workers per node
main_node_instance_types = [
  # Burstable - cheapest, good spot availability
  "t3a.medium",    # 2 vCPU, 4GB RAM - AMD (cheapest)
  "t3.medium",     # 2 vCPU, 4GB RAM - Intel
  "t3a.large",     # 2 vCPU, 8GB RAM - AMD
  "t3.large",      # 2 vCPU, 8GB RAM - Intel
  # General Purpose - good availability
  "m5.large",      # 2 vCPU, 8GB RAM - Intel
  "m5a.large",     # 2 vCPU, 8GB RAM - AMD (cheaper)
  "m5.xlarge",     # 4 vCPU, 16GB RAM - Intel
  "m5a.xlarge",    # 4 vCPU, 16GB RAM - AMD
  # Newer Generation - often available
  "m6i.large",     # 2 vCPU, 8GB RAM - Intel
  "m6a.large",     # 2 vCPU, 8GB RAM - AMD
  "m6i.xlarge",    # 4 vCPU, 16GB RAM - Intel
  "m6a.xlarge"     # 4 vCPU, 16GB RAM - AMD
]
main_node_min_size     = 1   # Minimum 1 node for Gateway scheduler
main_node_desired_size = 1   # Start with 1 node
main_node_max_size     = 80  # Support high node count
enable_spot_instances  = true

# Dask Node Group - DISABLED (using single node group)
# AWS requires max_size >= 1, but we keep min/desired at 0 so it never scales up
dask_node_instance_types = ["t3.medium"]  # Dummy value (not used)
dask_node_min_size       = 0              # Won't create any nodes
dask_node_desired_size   = 0              # Won't create any nodes
dask_node_max_size       = 1              # Minimum allowed by AWS (never reached)

# User Resource Limits - NOT USED (no JupyterHub users)
# Minimal values since no notebook servers will be created
user_cpu_guarantee    = 1
user_cpu_limit       = 2
user_memory_guarantee = "2G"
user_memory_limit    = "4G"

# Dask Worker Configuration - Optimized for CPU-bound workloads
# 1 core, 3GB per worker = ~2-3 workers per t3.medium node
dask_worker_cores_max  = 1      # 1 core per worker
dask_worker_memory_max = 3      # 3GB per worker
dask_cluster_max_cores = 240    # Max 240 cores (80 nodes * ~3 workers/node)

# Idle Timeouts
kernel_cull_timeout = 1200   # Not used (no notebooks)
server_cull_timeout = 3600   # 1 hour - Gateway cluster idle timeout

# S3 Configuration
s3_lifecycle_days = 30      # Standard retention
force_destroy_s3  = false   # Prevent accidental data loss

# Cost Optimization
scale_to_zero        = false  # Can't scale to zero - need 1 node for Gateway scheduler
enable_auto_shutdown = false  # No scheduled shutdown
enable_monitoring    = false  # No CloudWatch to save costs

# Safety
deletion_protection = false  # Allow deletion for testing
skip_final_snapshot = true

# Backup Configuration - Minimal
enable_backups        = false
backup_retention_days = 1
