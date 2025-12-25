# CAE-JupyterHub Migration Analysis

This document analyzes the differences between the existing `cae-jupyterhub` deployment (eksctl + Helm) and the `englacial` environment in `tofu_jupyter` (OpenTofu), providing recommendations for merging them into an upgraded CAE-JupyterHub deployment.

## Table of Contents
1. [Executive Summary](#executive-summary)
2. [Architecture Comparison](#architecture-comparison)
3. [Detailed Differences](#detailed-differences)
4. [Migration Recommendations](#migration-recommendations)
5. [Implementation Plan](#implementation-plan)

---

## Executive Summary

### Current State

| Aspect | cae-jupyterhub | englacial (tofu_jupyter) |
|--------|----------------|--------------------------|
| **IaC Tool** | eksctl + manual Helm | OpenTofu (automated) |
| **Cluster Management** | eksctl YAML | OpenTofu modules |
| **Helm Deployment** | Manual `helm install` | Automated via OpenTofu |
| **Node Architecture** | 2 node groups | 3 node groups (system/user/worker) |
| **Authentication** | Cognito OAuth | GitHub OAuth (with Cognito support) |
| **HTTPS** | Classic ELB + SSL | NLB + ACM SSL (better WebSocket) |
| **Cost Tracking** | None | Kubecost integrated |
| **Secrets** | Plain YAML (risky) | SOPS encrypted |
| **State** | kubectl/Helm state only | S3 + DynamoDB (versioned, locked) |

### Key Benefits of Migration

1. **Infrastructure as Code**: Full cluster lifecycle managed in Git
2. **Better Node Architecture**: Dedicated system node prevents user workloads from impacting hub
3. **Improved HTTPS**: NLB properly handles WebSocket connections for JupyterHub
4. **Cost Visibility**: Kubecost provides per-user and per-cluster cost tracking
5. **Security**: SOPS encryption, GitHub OIDC, proper IAM roles
6. **Profile Selection**: Users choose instance size at login (Small/Medium)

---

## Architecture Comparison

### Node Group Architecture

#### cae-jupyterhub (Current)
```
┌─────────────────────────────────────────────────────────────┐
│                    EKS Cluster: pangeo                       │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌───────────────────────┐   ┌───────────────────────────┐  │
│  │  main2 (r5n.xlarge)   │   │  dask-workers (m5.*)      │  │
│  │  On-Demand, 1-30      │   │  Spot, 1-30               │  │
│  │                       │   │  Tainted: lifecycle=spot  │  │
│  │  - JupyterHub Hub     │   │                           │  │
│  │  - JupyterHub Proxy   │   │  - Dask Scheduler         │  │
│  │  - User Notebooks     │   │  - Dask Workers           │  │
│  │  - Dask Gateway       │   │                           │  │
│  └───────────────────────┘   └───────────────────────────┘  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Issues with 2-node architecture**:
- Hub and user pods compete for resources on same nodes
- Heavy user workload can impact Hub stability
- Scale-to-zero affects Hub availability

#### englacial (OpenTofu - 3-Node Architecture)
```
┌─────────────────────────────────────────────────────────────────────────┐
│                    EKS Cluster: jupyterhub-englacial                     │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────┐  │
│  │  system (r5.large)  │  │  user (r5.large/xl) │  │  dask (m5.*)    │  │
│  │  On-Demand, fixed 1 │  │  On-Demand, 0-10    │  │  Spot, 0-100    │  │
│  │                     │  │  Scale to Zero      │  │  Tainted        │  │
│  │  - JupyterHub Hub   │  │                     │  │                 │  │
│  │  - JupyterHub Proxy │  │  - User Notebooks   │  │  - Dask Sched   │  │
│  │  - Dask Gateway     │  │  (Small or Medium)  │  │  - Dask Workers │  │
│  │  - Kubecost         │  │                     │  │                 │  │
│  │  - Cluster AutoSc   │  │                     │  │                 │  │
│  └─────────────────────┘  └─────────────────────┘  └─────────────────┘  │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

**Benefits**:
- Hub always stable on dedicated system node
- User pods don't compete with Hub resources
- Better cost tracking (separate node group costs)
- Profile selection: users choose Small (2 CPU) or Medium (4 CPU)

---

## Detailed Differences

### 1. Cluster Configuration

| Setting | cae-jupyterhub | englacial |
|---------|----------------|-----------|
| Cluster Name | `pangeo` | `jupyterhub-englacial` |
| K8s Version | 1.29 | 1.34 |
| AZs | us-west-2a, us-west-2b | us-west-2a, us-west-2b |
| VPC CIDR | eksctl default (192.168.0.0/16) | Custom (10.4.0.0/16) |
| Node Groups | 2 (main2, dask-workers) | 3 (system, user, dask) |

### 2. Main/System Node Configuration

| Setting | cae-jupyterhub (main2) | englacial (system) |
|---------|------------------------|-------------------|
| Instance Types | r5n.xlarge | r5.large |
| Min Size | 1 | 1 (fixed) |
| Max Size | 30 | 1 (fixed) |
| Pricing | On-Demand | On-Demand |
| Purpose | Hub + User pods | Hub + System services only |

**Key Difference**: englacial uses a smaller, fixed-size system node that only runs infrastructure, not user workloads. This is more cost-effective and stable.

### 3. User Node Configuration

| Setting | cae-jupyterhub | englacial (user) |
|---------|----------------|------------------|
| Exists? | No (users on main2) | Yes |
| Instance Types | N/A | r5.large, r5.xlarge |
| Min Size | N/A | 0 (scale to zero) |
| Max Size | N/A | 10 |
| Profile Selection | No | Yes (Small/Medium) |

**Key Difference**: englacial provides dedicated user node group with profile selection, allowing users to choose their resource allocation.

### 4. Dask Worker Configuration

| Setting | cae-jupyterhub | englacial |
|---------|----------------|-----------|
| Instance Types | m5.large → m5.4xlarge | m5.* + m5a.* (AMD) |
| Min Size | 1 | 0 |
| Max Size | 30 | 100 |
| Spot | Yes | Yes |
| Cores per Worker | 1-4 (user choice) | 1 (fixed) |
| Memory per Worker | 1-16 GB (user choice) | 3 GB (fixed) |
| Max Cluster Cores | 20 | 200 |

**Key Differences**:
- englacial includes AMD instances (m5a.*) for better spot availability
- englacial has optimized worker sizing (1 core, 3GB) for CPU-bound workloads
- englacial supports much larger clusters (200 cores vs 20)
- englacial can scale to zero (no idle cost)

### 5. JupyterHub Configuration

| Setting | cae-jupyterhub | englacial |
|---------|----------------|-----------|
| Image | pangeo/pangeo-notebook:2025.01.10 | pangeo/pangeo-notebook:2025.01.10 |
| CPU Guarantee | 2 | 1.6 (Small) / 3.5 (Medium) |
| CPU Limit | 4 | 2 (Small) / 4 (Medium) |
| Memory Guarantee | 15G | 14G (Small) / 28G (Medium) |
| Memory Limit | 30G | 15G (Small) / 30G (Medium) |
| Lifecycle Hooks | Yes (climakitae install) | Optional (configurable) |
| Profile Selection | No | Yes |

**Key Difference**: englacial uses profile-based resource allocation, giving users choice.

### 6. Authentication

| Setting | cae-jupyterhub | englacial |
|---------|----------------|-----------|
| Primary Auth | AWS Cognito OAuth | GitHub OAuth |
| Cognito Support | Yes (hardcoded) | Yes (optional) |
| GitHub Support | No | Yes |
| Allow All | Yes | Configurable |
| Org Whitelist | No | Yes (optional) |
| Callback URL | https://hub.cal-adapt.org | https://hub.englacial.org |

**Key Difference**: englacial supports GitHub OAuth (simpler for many teams) with optional org whitelisting.

### 7. HTTPS/SSL Configuration

| Setting | cae-jupyterhub | englacial |
|---------|----------------|-----------|
| Load Balancer Type | Classic ELB | Network Load Balancer (NLB) |
| SSL Termination | ELB | NLB |
| Certificate | Hardcoded ACM ARN | Dynamic (from ACM module) |
| Idle Timeout | 3600s | Unlimited (TCP mode) |
| WebSocket Support | Limited (HTTP mode) | Full (TCP mode) |

**Key Difference**: NLB in englacial properly handles WebSocket connections, preventing notebook disconnections.

### 8. S3 Scratch Bucket

| Setting | cae-jupyterhub | englacial |
|---------|----------------|-----------|
| Bucket | s3://cadcat-tmp/{user} | s3://{cluster-bucket}/{user} |
| IAM Access | IRSA (user-sa) | IRSA (user-sa) + Pod Identity |
| Lifecycle | Not configured | 30 days |

### 9. Secrets Management

| Setting | cae-jupyterhub | englacial |
|---------|----------------|-----------|
| Secrets Storage | Plain text in daskhub.yaml | SOPS encrypted secrets.yaml |
| Client Secret | In config file | Encrypted, loaded at runtime |
| Git Safety | Risk of exposure | Safe to commit |

**Key Difference**: englacial uses SOPS for secrets encryption, allowing safe Git commits.

### 10. Cost Monitoring

| Feature | cae-jupyterhub | englacial |
|---------|----------------|-----------|
| Kubecost | No | Yes |
| AWS CUR | No | Yes (integrated) |
| Per-user Costs | No | Yes |
| Per-cluster Costs | No | Yes |

---

## Migration Recommendations

### Recommended Approach: Incremental Migration

Rather than a "big bang" migration, we recommend an incremental approach:

1. **Phase 1: Deploy tofu_era alongside cae-jupyterhub**
   - Create new cluster using tofu_era
   - Configure with CAE-specific settings
   - Run both in parallel for testing

2. **Phase 2: Migrate Users Gradually**
   - Direct beta users to new cluster
   - Monitor for issues
   - Refine configuration

3. **Phase 3: DNS Cutover**
   - Update hub.cal-adapt.org to point to new cluster
   - Keep old cluster as fallback

4. **Phase 4: Decommission Old Cluster**
   - After 2-4 weeks of stable operation
   - Export any needed data
   - Destroy old cluster

### CAE-Specific Configuration

Create `environments/cae/terraform.tfvars`:

```hcl
# CAE-JupyterHub Configuration
# Based on englacial architecture with CAE-specific settings

# =============================================================================
# ENVIRONMENT SETTINGS
# =============================================================================
environment  = "cae"
region       = "us-west-2"
cluster_name = "jupyterhub"  # → jupyterhub-cae
domain_name  = "hub.cal-adapt.org"
admin_email  = "bgaley@berkeley.edu"
owner_email  = "cae-team@berkeley.edu"
cost_center  = "cae-research"

# Kubernetes - upgrade to latest
kubernetes_version = "1.34"

# =============================================================================
# NETWORK CONFIGURATION
# =============================================================================
# Use different CIDR than englacial to allow VPC peering if needed
vpc_cidr                  = "10.5.0.0/16"
enable_nat_gateway        = true
single_nat_gateway        = true
pin_user_nodes_single_az  = true

# =============================================================================
# 3-NODE ARCHITECTURE (from englacial)
# =============================================================================
use_three_node_groups = true

# System Node - Hub + Services
system_node_instance_types = ["r5.large"]
system_node_min_size       = 1
system_node_desired_size   = 1
system_node_max_size       = 1

# User Node - Notebooks (scale to zero)
user_node_instance_types = ["r5.large", "r5.xlarge"]
user_node_min_size       = 0
user_node_desired_size   = 0
user_node_max_size       = 10

# Dask Worker Nodes (scale to zero, spot)
dask_node_instance_types = [
  "m5.large", "m5.xlarge", "m5.2xlarge", "m5.4xlarge",
  "m5a.large", "m5a.xlarge", "m5a.2xlarge", "m5a.4xlarge"
]
dask_node_min_size       = 0
dask_node_desired_size   = 0
dask_node_max_size       = 50

# =============================================================================
# SPOT CONFIGURATION
# =============================================================================
system_enable_spot_instances = false
user_enable_spot_instances   = false
dask_enable_spot_instances   = true

# =============================================================================
# USER RESOURCES (from cae-jupyterhub - preserve current experience)
# =============================================================================
# Option 1: Keep fixed resources like current deployment
enable_profile_selection = false
user_cpu_guarantee    = 2
user_cpu_limit        = 4
user_memory_guarantee = "15G"
user_memory_limit     = "30G"

# Option 2: Enable profile selection (recommended for cost savings)
# enable_profile_selection = true
# (Users choose Small: 2 CPU/14GB or Medium: 4 CPU/28GB)

# =============================================================================
# DASK CONFIGURATION (from cae-jupyterhub)
# =============================================================================
dask_worker_cores_max  = 4    # Keep current user flexibility
dask_worker_memory_max = 16   # Keep current user flexibility
dask_cluster_max_cores = 20   # Start with current limit, can increase later

# =============================================================================
# IDLE TIMEOUTS (from cae-jupyterhub)
# =============================================================================
kernel_cull_timeout = 1200  # 20 minutes
server_cull_timeout = 1800  # 30 minutes (Dask cluster idle timeout from current config)

# =============================================================================
# AUTHENTICATION
# =============================================================================
# Option 1: Keep Cognito (current)
# Note: Requires cognito module configuration

# Option 2: Switch to GitHub (simpler)
github_enabled       = false  # Change to true when ready
github_org_whitelist = ""     # Set to org name if needed

# =============================================================================
# CONTAINER IMAGE
# =============================================================================
singleuser_image_name = "pangeo/pangeo-notebook"
singleuser_image_tag  = "2025.01.10"

# =============================================================================
# HTTPS/SSL
# =============================================================================
enable_acm          = true
acm_enable_wildcard = true   # For *.cal-adapt.org
acm_auto_validate   = false  # Manual DNS validation

# =============================================================================
# COST MONITORING
# =============================================================================
enable_kubecost = true

# =============================================================================
# S3 CONFIGURATION
# =============================================================================
s3_lifecycle_days = 30
force_destroy_s3  = false

# =============================================================================
# SAFETY
# =============================================================================
deletion_protection = true
skip_final_snapshot = false
```

### Custom Lifecycle Hooks for CAE

The cae-jupyterhub has custom lifecycle hooks that install `climakitae`. To preserve this:

**Option 1: Bake into Custom Image** (Recommended)
Create a custom Docker image that includes climakitae pre-installed:

```dockerfile
FROM pangeo/pangeo-notebook:2025.01.10

RUN pip install --no-deps \
    git+https://github.com/cal-adapt/climakitae.git \
    git+https://github.com/cal-adapt/climakitaegui.git
```

**Option 2: Keep Lifecycle Hooks**
Configure in helm module variables (requires adding support).

### Cognito Configuration for CAE

Create `environments/cae/secrets.yaml` (encrypt with SOPS):

```yaml
cognito:
  client_secret: "YOUR_COGNITO_CLIENT_SECRET"
  client_id: "3jesa7vt6hanjscanmj93cj2kg"
  domain: "cae.auth.us-west-1.amazoncognito.com"
```

Modify helm module to support Cognito URLs for CAE:
- authorize_url: https://cae.auth.us-west-1.amazoncognito.com/oauth2/authorize
- token_url: https://cae.auth.us-west-1.amazoncognito.com/oauth2/token
- userdata_url: https://cae.auth.us-west-1.amazoncognito.com/oauth2/userInfo

---

## Implementation Plan

### Phase 1: Environment Setup (Week 1)

1. **Create CAE environment directory**
   ```bash
   mkdir -p environments/cae
   # Create terraform.tfvars from template above
   # Create backend.tfvars for S3 state
   # Create secrets.yaml with Cognito credentials
   ```

2. **Add Cognito module support**
   - Ensure cognito module supports external Cognito (CAE's pool is in us-west-1)
   - Or create `cognito_external` configuration option

3. **Add lifecycle hooks support**
   - Add variables for custom post-start commands
   - Or document custom image approach

### Phase 2: Infrastructure Deployment (Week 2)

1. **Deploy infrastructure**
   ```bash
   make init ENVIRONMENT=cae
   make plan ENVIRONMENT=cae
   make apply ENVIRONMENT=cae
   ```

2. **Configure DNS**
   - Create temporary domain (e.g., cae-new.cal-adapt.org)
   - Point to new cluster's NLB

3. **Test deployment**
   - Login with Cognito
   - Start notebook
   - Create Dask cluster
   - Verify climakitae works

### Phase 3: User Migration (Week 3-4)

1. **Beta testing**
   - Invite 3-5 power users to test
   - Collect feedback
   - Fix issues

2. **Documentation**
   - Update user docs for any changes
   - Document new features (profile selection if enabled)

### Phase 4: Cutover (Week 5)

1. **DNS update**
   - Change hub.cal-adapt.org to new cluster
   - Monitor for issues

2. **Fallback plan**
   - Keep old cluster running
   - Document rollback procedure

### Phase 5: Cleanup (Week 6+)

1. **Decommission old cluster**
   - After 2 weeks of stable operation
   - Export any user data
   - Run `eksctl delete cluster`

---

## Feature Comparison Summary

| Feature | Keep from CAE | Adopt from Englacial | Notes |
|---------|---------------|---------------------|-------|
| Cognito Auth | Yes | - | Existing user base |
| 3-Node Architecture | - | Yes | Better stability |
| NLB for HTTPS | - | Yes | Better WebSocket support |
| Profile Selection | Optional | Yes | Recommend enabling |
| Dask Config | Flexible (1-4 cores) | Fixed (1 core) | Keep CAE's flexibility |
| climakitae | Yes | - | Via custom image |
| Kubecost | - | Yes | Cost visibility |
| SOPS Secrets | - | Yes | Security |
| Scale to Zero | - | Yes | Cost savings |

---

## Questions to Resolve

Before proceeding, we should clarify:

1. **Profile Selection**: Do CAE users want to choose instance size at login, or prefer the current fixed allocation?

2. **Dask Worker Sizing**: The current config allows users to choose 1-4 cores per worker. Englacial uses fixed 1 core. Which is preferred?

3. **Authentication**: Stay with Cognito or migrate to GitHub OAuth?

4. **Domain**: Keep hub.cal-adapt.org or use new domain?

5. **Lifecycle Hooks vs Custom Image**: Install climakitae at runtime (current) or bake into image (faster startup)?

6. **Timeline**: When is the target date for migration completion?
