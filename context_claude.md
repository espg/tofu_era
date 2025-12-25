# Claude Context: tofu_era Project

**Last Updated**: 2025-12-25
**Previous Session Summary**: Initial project setup and documentation creation

---

## Project Overview

`tofu_era` is a new repository forked from `tofu_jupyter` at commit `6afaffd5ea8b03955fed14be9752c9e7505ad766`. The goal is to create an upgraded version of `cae-jupyterhub` by merging the best of both deployments.

### Related Repositories

| Repository | Location | Description |
|------------|----------|-------------|
| **tofu_era** | `/home/espg/era/tofu_era` | THIS REPO - new unified deployment |
| **tofu_jupyter** | `/home/espg/era/tofu_jupyter` | Source repo with OpenTofu JupyterHub |
| **cae-jupyterhub** | `/home/espg/era/cae-jupyterhub` | Existing CAE deployment (eksctl + Helm) |
| **era-jupyterhub** | `/home/espg/era/era-jupyterhub` | Documentation and notebooks for CAE |

---

## What Was Completed

### 1. Repository Created
- Forked from tofu_jupyter commit `6afaffd`
- Contains full OpenTofu configuration for JupyterHub on EKS
- Includes modules: acm, cognito, eks, helm, irsa, kms, kubecost, kubernetes, monitoring, networking, s3

### 2. Documentation Written (in `docs/`)

| File | Content |
|------|---------|
| `GITHUB_ACTIONS_OPENTOFU.md` | CI/CD setup guide - OIDC auth, workflows, environment protection |
| `ENVIRONMENT_SYNC_STRATEGY.md` | Makefile targets for syncing config between test/prod environments |
| `CAE_JUPYTERHUB_MIGRATION_ANALYSIS.md` | **KEY FILE** - Detailed comparison and migration plan |
| `README.md` | Overview of all docs |

### 3. Files Staged for Commit
All files are `git add`ed but NOT committed (user handles commits).

---

## Key Architecture Differences

### cae-jupyterhub (Current - eksctl)
```
2-Node Architecture:
├── main2 (r5n.xlarge, on-demand, 1-30 nodes)
│   ├── JupyterHub Hub
│   ├── JupyterHub Proxy
│   ├── User Notebooks (compete with Hub!)
│   └── Dask Gateway
└── dask-workers (m5.*, spot, 1-30 nodes)
    └── Dask Workers
```

### englacial/tofu_era (New - OpenTofu)
```
3-Node Architecture:
├── system (r5.large, on-demand, FIXED at 1)
│   ├── JupyterHub Hub
│   ├── JupyterHub Proxy
│   ├── Dask Gateway
│   └── Kubecost
├── user (r5.large/xlarge, on-demand, 0-10, SCALE TO ZERO)
│   └── User Notebooks (isolated from Hub!)
└── dask (m5.*/m5a.*, spot, 0-100)
    └── Dask Workers
```

### Key Improvements in tofu_era
1. **Dedicated system node** - Hub never competes with user workloads
2. **NLB instead of Classic ELB** - Proper WebSocket support
3. **Profile selection** - Users choose Small (2 CPU) or Medium (4 CPU)
4. **Kubecost** - Cost tracking per user/cluster
5. **SOPS encryption** - Secrets safe in Git
6. **Scale to zero** - User/worker nodes scale down when idle

---

## Questions to Resolve (from migration doc)

These are in `docs/CAE_JUPYTERHUB_MIGRATION_ANALYSIS.md` under "Questions to Resolve":

### 1. Profile Selection
**Question**: Do CAE users want to choose instance size at login, or prefer the current fixed allocation?
- Current (cae): Fixed 2 CPU / 15GB for all users
- New option: Small (2 CPU/14GB) or Medium (4 CPU/28GB) choice at login
- **Trade-off**: More flexibility vs simpler UX

### 2. Dask Worker Sizing
**Question**: Keep flexible (1-4 cores per worker) or use fixed (1 core)?
- Current (cae): Users choose 1-4 cores, 1-16GB per worker
- Englacial: Fixed 1 core, 3GB per worker (optimized for CPU-bound)
- **Trade-off**: User flexibility vs optimized packing

### 3. Authentication Method
**Question**: Stay with Cognito or migrate to GitHub OAuth?
- Current (cae): AWS Cognito in us-west-1
- Englacial: GitHub OAuth with optional org whitelist
- **Note**: Cognito requires us-west-1 region (cluster is in us-west-2)

### 4. Domain Name
**Question**: Keep hub.cal-adapt.org or use new domain?
- If keeping: DNS cutover required
- If new: Can run both in parallel during migration

### 5. Lifecycle Hooks vs Custom Image
**Question**: Install climakitae at runtime or bake into Docker image?
- Current (cae): postStart hook runs pip install
- Alternative: Pre-build image with climakitae included
- **Trade-off**: Flexibility vs faster pod startup

### 6. Timeline
**Question**: Target date for migration completion?
- Suggested phases: Setup (1 wk) → Deploy (1 wk) → Migrate users (2 wk) → Cutover (1 wk)

---

## CAE-Specific Configuration Template

A draft `environments/cae/terraform.tfvars` was included in the migration doc. Key settings:

```hcl
environment  = "cae"
domain_name  = "hub.cal-adapt.org"
vpc_cidr     = "10.5.0.0/16"  # Different from englacial's 10.4.0.0/16

# 3-node architecture
use_three_node_groups = true

# Preserve current CAE behavior (pending answers to questions above)
enable_profile_selection = false  # or true?
dask_worker_cores_max    = 4      # or 1?
github_enabled           = false  # or true?
```

---

## Next Steps

1. **Answer the 6 questions above** with the user
2. **Create environments/cae/** directory with finalized config
3. **Handle Cognito integration** if keeping (needs module updates for external Cognito)
4. **Handle climakitae** - either update lifecycle hooks or create custom image
5. **Test deployment** in parallel with existing cae-jupyterhub
6. **Plan DNS cutover** strategy

---

## Important Files to Read

When resuming, read these to understand context:

1. `/home/espg/era/tofu_era/docs/CAE_JUPYTERHUB_MIGRATION_ANALYSIS.md` - The main analysis
2. `/home/espg/era/cae-jupyterhub/daskhub.yaml` - Current CAE Helm values
3. `/home/espg/era/cae-jupyterhub/eks/cluster.yaml` - Current CAE eksctl config
4. `/home/espg/era/tofu_era/environments/englacial/terraform.tfvars` - Reference config
5. `/home/espg/era/tofu_era/modules/helm/main.tf` - Helm module (may need Cognito updates)

---

## Commands Reference

```bash
# Work in tofu_era
cd /home/espg/era/tofu_era

# Check current status
git status

# Create CAE environment
mkdir -p environments/cae
# Then create terraform.tfvars, backend.tfvars, secrets.yaml

# Test deployment
make init ENVIRONMENT=cae
make plan ENVIRONMENT=cae
```

---

## User Preferences Noted

- User handles git commits (Claude does `git add` only)
- Check CLAUDE.md in repos for instructions
- Prefer editing existing files over creating new ones
