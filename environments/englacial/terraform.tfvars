# Terra JupyterHub - Englacial Environment Configuration
# Cost-optimized environment with 3-node architecture:
#   - System node (r5.large, always on) - Hub + Monitoring
#   - User nodes (r5.xlarge, scale 0→N) - User pods
#   - Worker nodes (m5.*/m5a.*, spot, scale 0→N) - Dask workers

# Core Settings
environment  = "englacial"
region      = "us-west-2"
cluster_name = "jupyterhub"  # Will become: jupyterhub-englacial (env appended by main.tf)
domain_name  = "hub.englacial.org"  # Production domain
admin_email  = "admin@example.com"
owner_email  = "devops@example.com"
cost_center  = "research"

# Kubernetes
kubernetes_version = "1.34"

# ACM Certificate - ENABLED for HTTPS production deployment
enable_acm          = true   # Enable SSL certificate
acm_enable_wildcard = false  # Just hub.englacial.org (not *.englacial.org)
acm_auto_validate   = false  # Manual DNS validation (you control DNS)

# Network Configuration - Cost-Optimized
# S3 VPC Gateway Endpoint configured in networking module (no NAT costs for S3!)
vpc_cidr                  = "10.4.0.0/16"  # Unique CIDR for englacial
enable_nat_gateway        = true           # Required for private subnets
single_nat_gateway        = true           # Single NAT to save $45/month
pin_main_nodes_single_az  = false          # Not needed with 3-node-group architecture
pin_user_nodes_single_az  = true           # Pin to us-west-2a to fix PVC zone affinity

# Node Group - System (Always Running) - r5.large
# Runs: JupyterHub Hub, Kubecost, Prometheus, System pods
# This is the "system" node group that replaces the old "main" node group
system_node_instance_types = ["r5.large"]  # 2 vCPU, 16GB RAM
system_node_min_size       = 1             # Always 1 (fixed)
system_node_desired_size   = 1
system_node_max_size       = 1             # Cannot scale (dedicated system node)

# Node Group - User (Scale to Zero) - r5.large or r5.xlarge
# Runs: JupyterHub user pods (notebooks)
# Scales up when user logs in, scales down when idle
# Users can select Small (r5.large) or Medium (r5.xlarge) at login
user_node_instance_types = ["r5.large", "r5.xlarge"]  # Small: 2 vCPU, 16GB | Medium: 4 vCPU, 32GB
user_node_min_size       = 0               # Scale to zero when idle
user_node_desired_size   = 0
user_node_max_size       = 10              # Support up to 10 concurrent users

# Node Group - Dask Workers (Scale to Zero) - Spot Instances
# Runs: Dask worker pods
# Using non-SSD instances for better spot availability
dask_node_instance_types = [
  "m5.large",      # 2 vCPU, 8GB RAM - Intel
  "m5.xlarge",     # 4 vCPU, 16GB RAM - Intel
  "m5.2xlarge",    # 8 vCPU, 32GB RAM - Intel
  "m5.4xlarge",    # 16 vCPU, 64GB RAM - Intel
  "m5a.large",     # 2 vCPU, 8GB RAM - AMD (cheaper, better availability)
  "m5a.xlarge",    # 4 vCPU, 16GB RAM - AMD
  "m5a.2xlarge",   # 8 vCPU, 32GB RAM - AMD
  "m5a.4xlarge"    # 16 vCPU, 64GB RAM - AMD
]
dask_node_min_size       = 0               # Start at zero
dask_node_desired_size   = 0               # Scale on demand
dask_node_max_size       = 100             # Support large clusters

# Spot Instance Configuration
system_enable_spot_instances = false       # System: ON-DEMAND (stability)
user_enable_spot_instances   = false       # User: ON-DEMAND (user experience)
dask_enable_spot_instances   = true        # Dask: SPOT (cost savings)

# JupyterLab Profile Selection - Users choose instance size at login
# Small (default): r5.large - 2 vCPU, 14 GB - $0.126/hr
# Medium: r5.xlarge - 4 vCPU, 28 GB - $0.252/hr
enable_profile_selection = true

# User Resource Limits (only used when enable_profile_selection = false)
# These are legacy settings - when profiles are enabled, resources are set per-profile
user_cpu_guarantee    = 3      # 3 cores guaranteed
user_cpu_limit        = 4      # 4 cores max (full node)
user_memory_guarantee = "24G"  # 24GB guaranteed
user_memory_limit     = "30G"  # 30GB max (leaving 2GB for system)

# Dask Worker Configuration - Optimized for CPU-bound workloads
dask_worker_cores_max  = 1     # 1 core per worker
dask_worker_memory_max = 3     # 3GB per worker
dask_cluster_max_cores = 200   # Max 200 cores per cluster

# Idle Timeouts
kernel_cull_timeout = 1200  # 20 minutes
server_cull_timeout = 3600  # 60 minutes

# S3 Configuration
s3_lifecycle_days = 30      # Delete after 30 days
force_destroy_s3  = true    # Allow easy cleanup

# Cost Optimization
scale_to_zero        = false  # Not applicable (user/worker nodes scale independently)
enable_auto_shutdown = false  # Keep system node running for monitoring
enable_monitoring    = false  # No CloudWatch to save costs

# Kubecost Configuration
enable_kubecost = true       # Enable cost monitoring with AWS CUR integration

# Safety
deletion_protection = false  # Allow easy deletion for testing
skip_final_snapshot = true

# Backup Configuration
enable_backups        = false
backup_retention_days = 1

# Deployment Type
enable_jupyterhub = true     # Full JupyterHub deployment

# Node Group Architecture
use_three_node_groups = true  # Use 3-node architecture (system, user, worker)

# GitHub OAuth Authentication (Production)
github_enabled = true         # Enable GitHub OAuth for real authentication
github_org_whitelist = ""     # Optional: Add your GitHub org name to restrict access
                              # Example: "your-org-name" to allow only org members
