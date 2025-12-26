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

---

## Session: 2025-12-25 (Evening) - CI/CD & Environment Setup

### AWS Account Context

| Account | Purpose | Credentials |
|---------|---------|-------------|
| 992398409787 | cae-dev, cae-testing, cae | `../aws-key-id-secret-pair.txt` |
| 429435741471 | englacial (tofu_jupyter) | Default AWS profile |

### What Was Completed

#### 1. Cleaned Up Old Resources (Account 992398409787)
- Deleted orphaned CloudFormation stacks from old eksctl-pangeo-cluster
- Deleted NAT Gateway, Classic ELB in us-west-1
- Scheduled 5 customer-managed KMS keys for deletion (~$59/month savings)

#### 2. GitHub Actions CI/CD Setup
- Created `.github/workflows/tofu.yml` - Main CI/CD (plan on PR, apply on merge)
- Created `.github/workflows/tofu-destroy.yml` - Safety-gated destroy workflow
- Workflows now use Makefile (`make plan`, `make init`) for consistency
- **Uses OIDC authentication** - no static credentials

#### 3. IAM Role for GitHub Actions
- Created OIDC identity provider (already existed)
- Created role: `arn:aws:iam::992398409787:role/github-actions-tofu-era`
- Trust policy: `repo:espg/tofu_era:*`
- Attached: AdministratorAccess

**GitHub Setup Required:**
- Create environment `cae-testing` with variable `AWS_ROLE_ARN`
- Create environment `cae-dev` with variable `AWS_ROLE_ARN`
- Create environment `cae` with variable `AWS_ROLE_ARN` + required reviewers

#### 4. Makefile Improvements
- Fixed SOPS/KMS key ordering issue with new `check-sops-config` target
- Automatically creates KMS key and updates `.sops.yaml` for new environments
- Fixed `describe-alias` (doesn't exist) → use `list-aliases` + `describe-key`

#### 5. Created `backend.tf`
- S3 backend block was missing, causing "Missing backend configuration" warning
- Now properly stores state in S3

#### 6. Removed englacial Environment
- Deleted `environments/englacial/` directory
- Removed from `.sops.yaml`
- Removed from workflow options

#### 7. cae-dev Environment Setup
- Domain: `cae-dev.rocktalus.com`
- ACM enabled with manual DNS validation (no Route53)
- **Created Cognito user pool** in us-west-1:
  - Pool ID: `us-west-1_iIJnsmn4m`
  - Client ID: `4fumjktp49ajd8tvrf6glevbfr`
  - Domain: `cae-dev-hub.auth.us-west-1.amazoncognito.com`
- Secrets encrypted with KMS key in 992398409787

#### 8. cae-testing Environment (In Progress)
- Branch: `add-cae-testing`
- Minimal testing environment with **dummy auth** (no login required)
- No domain (uses load balancer URL directly)
- Smaller instances, aggressive timeouts, no Kubecost

### Current Git State

**main branch** (2 commits ahead of origin):
```
dd37e92 base minimal conf for working cae hub
8d31e71 Update workflows to include cae-testing option, add tfplan to gitignore
```

**add-cae-testing branch** (1 commit ahead of main):
```
2f334e2 Add cae-testing environment for CI/CD testing
```

**Needs to be pushed:**
```bash
git checkout main && git push origin main
git checkout add-cae-testing && git push -u origin add-cae-testing
# Then create PR to test GitHub Actions workflow
```

### Pending Tasks

1. **Push main** to origin
2. **Create GitHub environments** (cae-testing, cae-dev, cae) with `AWS_ROLE_ARN` variable
3. **Push add-cae-testing branch** and create PR to test workflow
4. **Complete cae-dev deployment** - run `make apply ENVIRONMENT=cae-dev`
5. **Post-apply for cae-dev:**
   - Add ACM validation CNAME to DNS
   - Add load balancer CNAME for `cae-dev.rocktalus.com`
   - Create user in Cognito user pool

### Key Files Modified This Session

| File | Change |
|------|--------|
| `.github/workflows/tofu.yml` | Created - uses Makefile |
| `.github/workflows/tofu-destroy.yml` | Created |
| `backend.tf` | Created - S3 backend block |
| `Makefile` | Added `check-sops-config` target, fixed AWS CLI commands |
| `.sops.yaml` | Cleaned up, now auto-populated by Makefile |
| `environments/cae-dev/*` | Configured with Cognito, ACM, proper settings |
| `environments/cae-testing/*` | New minimal testing environment |
| `.gitignore` | Added `tfplan` |

### Commands Reference (This Session)

```bash
# Switch to cae-dev account
export AWS_ACCESS_KEY_ID=AKIA6OD4OAA5TCKF7NT2
export AWS_SECRET_ACCESS_KEY='<see ../aws-key-id-secret-pair.txt>'

# Fish shell version
set -x AWS_ACCESS_KEY_ID AKIA6OD4OAA5TCKF7NT2
set -x AWS_SECRET_ACCESS_KEY '<secret>'

# Deploy cae-dev
make plan ENVIRONMENT=cae-dev
make apply ENVIRONMENT=cae-dev

# Check outputs after apply
make output ENVIRONMENT=cae-dev
make status ENVIRONMENT=cae-dev
```

### Cognito Details (cae-dev)

```
Region: us-west-1
User Pool ID: us-west-1_iIJnsmn4m
User Pool Name: cae-dev-jupyterhub
App Client ID: 4fumjktp49ajd8tvrf6glevbfr
Domain: cae-dev-hub.auth.us-west-1.amazoncognito.com
Callback URL: https://cae-dev.rocktalus.com/hub/oauth_callback
```

To create a user:
```bash
aws cognito-idp admin-create-user \
  --user-pool-id us-west-1_iIJnsmn4m \
  --username user@example.com \
  --temporary-password TempPass123! \
  --region us-west-1
```

---

## Session: 2025-12-25 (Night) - JupyterHub Features Implementation

### Tasks Completed

#### 1. VSCode Integration
- Created `docker/Dockerfile` extending `pangeo/pangeo-notebook` with:
  - `code-server` (VS Code in browser)
  - `jupyter-vscode-proxy` for JupyterLab integration
- Added new variables to helm module:
  - `enable_vscode` - Enable VSCode access
  - `default_url` - Set default landing page (/lab, /vscode, /tree)
- VSCode accessible at `/vscode` URL path when enabled

#### 2. Custom Image Selection at Login
- Implemented `unlisted_choice` support in profileList
- Users can:
  - Choose from predefined image options
  - Specify any custom Docker image (format: `image:tag`)
- Added new variables:
  - `enable_custom_image_selection` - Allow custom image input
  - `additional_image_choices` - List of pre-defined image options
- cae-testing configured with SciPy and Data Science notebook options

#### 3. Research: SSH Access to JupyterHub
**Approach:** Deploy [jupyterhub-ssh](https://github.com/yuvipanda/jupyterhub-ssh) Helm chart

**Requirements:**
- Separate Helm release alongside JupyterHub
- Dedicated LoadBalancer/port (typically port 22 or 8022)
- DNS record for SSH endpoint
- Users authenticate with JupyterHub API tokens (not SSH keys)

**Limitations:**
- No SSH key support (token-only)
- No SSH tunneling/port forwarding
- SFTP requires NFS-based home directories
- Project still in active development

**Not implemented** - requires additional infrastructure decisions

#### 4. Research: JupyterHub Version Upgrade

**Current versions (DaskHub 2024.1.1):**
- JupyterHub: 4.0.2
- Dask Gateway: 2024.1.0

**Latest available:**
- DaskHub (development): JupyterHub 4.3.2, Dask Gateway 2025.4.0
- Z2JH 4.0: JupyterHub 5.2.1 (Nov 2024)

**Upgrade path:**
1. Update `modules/helm/main.tf` line 99: `version = "2024.1.1"` → newer
2. Test on cae-testing first
3. Review changelog for breaking changes

### Files Modified

| File | Change |
|------|--------|
| `docker/Dockerfile` | NEW - Custom image with VSCode support |
| `modules/helm/main.tf` | Added image selection, unlisted_choice, defaultUrl |
| `modules/helm/variables.tf` | Added enable_vscode, default_url, image selection vars |
| `variables.tf` | Added new vars, fixed environment validation |
| `main.tf` | Pass new vars to helm module |
| `environments/cae-testing/terraform.tfvars` | Enable VSCode + custom images |

### cae-testing Environment Configuration

New features enabled:
```hcl
# VSCode Integration
enable_vscode = true
default_url   = "/lab"  # VSCode at /vscode

# Custom Image Selection
enable_custom_image_selection = true
additional_image_choices = [
  {
    name         = "jupyter/scipy-notebook:2024-12-09"
    display_name = "SciPy Notebook"
    description  = "Jupyter's official SciPy notebook"
  },
  {
    name         = "jupyter/datascience-notebook:2024-12-09"
    display_name = "Data Science Notebook"
    description  = "Full data science stack with Python, R, and Julia"
  }
]
```

### Important Notes

**VSCode via py-rocket-base:**
Instead of building a custom image, cae-testing now uses `ghcr.io/nmfs-opensci/py-rocket-base` which includes:
- VSCode (code-server) at `/vscode`
- RStudio at `/rstudio`
- Desktop VNC at `/desktop`
- Pangeo-compatible Python stack

**Custom Dockerfile (for future use):**
The `docker/Dockerfile` is kept for when we set up GitHub Actions CI/CD to build custom images with exactly the packages we need.

### Next Steps

1. Deploy cae-testing: `make apply ENVIRONMENT=cae-testing`
2. Test VSCode access at `/vscode`
3. Test RStudio at `/rstudio` (bonus!)
4. Test custom image selection at login
5. Set up GitHub Actions + ECR for custom image building (Part C)
6. Decide on SSH access approach (if needed)
