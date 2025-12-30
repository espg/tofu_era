# tofu_era Documentation

This directory contains documentation for the tofu_era project - an OpenTofu-based JupyterHub deployment on AWS EKS.

## Documents

### 0. [SHANE_ARCHITECTURE_NOTES.md](./SHANE_ARCHITECTURE_NOTES.md)

Overview of how things work (and why)

### 1. [GITHUB_ACTIONS_OPENTOFU.md](./GITHUB_ACTIONS_OPENTOFU.md)

**Purpose**: Guide for setting up GitHub Actions to trigger OpenTofu builds on git commits.

**Key Topics**:
- AWS OIDC authentication (recommended) vs IAM access keys
- Workflow files for plan/apply/destroy
- Environment protection rules
- SOPS secrets integration
- State locking considerations
- Step-by-step implementation guide

**Quick Start**:
1. Set up AWS OIDC provider
2. Create IAM role with trust policy for GitHub
3. Add workflow files to `.github/workflows/`
4. Configure GitHub environments with protection rules

---

### 2. [EKS_CLUSTER_ACCESS.md](./EKS_CLUSTER_ACCESS.md)

**Purpose**: Explains how IAM users and roles are granted access to EKS clusters via the `aws-auth` ConfigMap.

**Key Topics**:
- How EKS authentication works
- Configuring `cluster_admin_roles` and `cluster_admin_users`
- Adding new developers or CI/CD roles
- Debugging "Unauthorized" errors
- Emergency manual fixes

**Quick Reference**:
```hcl
# In terraform.tfvars
cluster_admin_roles = [
  { arn = "arn:aws:iam::ACCOUNT:role/github-actions", username = "github-actions" }
]
cluster_admin_users = [
  { arn = "arn:aws:iam::ACCOUNT:user/developer", username = "developer" }
]
```

---

### 4. [ENVIRONMENT_SYNC_STRATEGY.md](./ENVIRONMENT_SYNC_STRATEGY.md)

**Purpose**: Strategy for synchronizing configuration changes between testing and production environments.

**Key Topics**:
- Three-layer configuration model (defaults → features → overrides)
- Makefile targets for syncing (sync-features-from, sync-features-to, sync-diff)
- Promoting features from test to production
- Backporting production settings to development
- Safety considerations

**Key Commands**:
```bash
# Extract features from test environment
make sync-features-from SYNC_SOURCE=englacial

# Apply to production
make sync-features-to SYNC_TARGET=prod

# Compare two environments
make sync-diff SYNC_SOURCE=englacial SYNC_TARGET=prod

# One-step promote (test → prod)
make sync-promote SYNC_SOURCE=englacial SYNC_TARGET=prod
```

---

### 5. [CAE_JUPYTERHUB_MIGRATION_ANALYSIS.md](./CAE_JUPYTERHUB_MIGRATION_ANALYSIS.md)

**Purpose**: Analysis of differences between the existing `cae-jupyterhub` (eksctl + Helm) and the `englacial` environment (OpenTofu), with migration recommendations.

**Key Topics**:
- Architecture comparison (2-node vs 3-node)
- Detailed configuration differences
- CAE-specific configuration template
- Migration recommendations (incremental approach)
- Implementation phases and timeline
- Questions to resolve before migration

**Key Differences Summary**:

| Aspect | cae-jupyterhub | englacial (OpenTofu) |
|--------|----------------|---------------------|
| IaC | eksctl + manual Helm | OpenTofu (automated) |
| Nodes | 2 groups | 3 groups (system/user/worker) |
| Auth | Cognito | GitHub (Cognito optional) |
| HTTPS | Classic ELB | NLB (better WebSocket) |
| Costs | No tracking | Kubecost integrated |
| Secrets | Plain text | SOPS encrypted |

---

### 6. [BLUE_GREEN_MIGRATION_PLAN.md](./BLUE_GREEN_MIGRATION_PLAN.md)

**Purpose**: Step-by-step blue/green deployment plan for migrating from cae-jupyterhub to tofu_era.

**Key Topics**:
- Timeline (2-week migration window)
- DNS cutover procedure
- Rollback plan
- User communication templates
- **Storage migration: gp2 to gp3**
- User data backup instructions

**Storage Migration Summary**:

| Data Type | Migration Required? |
|-----------|---------------------|
| S3 scratch (`cadcat-tmp`) | No - preserved |
| Home directory (EBS PVC) | Yes - new gp3 volumes |
| Notebooks (git) | No - auto-pulled |

---

### 7. [JUPYTERHUB_SSH_RESEARCH.md](./JUPYTERHUB_SSH_RESEARCH.md)

**Purpose**: Research notes on enabling SSH access to JupyterHub via jupyterhub-ssh.

**Key Topics**:
- How jupyterhub-ssh works
- Authentication (API tokens, not SSH keys)
- What works (SSH terminal) vs doesn't work (SCP, port forwarding)
- Infrastructure requirements (separate NLB)
- Cost analysis (~$17-21/month)

**Status**: Research complete, not yet implemented.

---

## Repository Structure

```
tofu_era/
├── main.tf                 # Main OpenTofu configuration
├── variables.tf            # Variable definitions
├── outputs.tf              # Output definitions
├── encryption.tf           # State encryption config
├── Makefile               # Build automation
├── .sops.yaml             # SOPS encryption rules
├── .gitignore
├── environments/          # Environment-specific configs
│   ├── dev/
│   ├── staging/
│   ├── englacial/
│   └── cae/               # (to be created)
├── modules/               # OpenTofu modules
│   ├── acm/              # SSL certificates
│   ├── cognito/          # Authentication
│   ├── eks/              # Kubernetes cluster
│   ├── helm/             # Helm releases
│   ├── kms/              # Encryption keys
│   ├── kubernetes/       # K8s resources
│   ├── networking/       # VPC, subnets
│   └── s3/               # Storage
├── scripts/               # Utility scripts
└── docs/                  # This directory
    ├── README.md
    ├── GITHUB_ACTIONS_OPENTOFU.md
    ├── EKS_CLUSTER_ACCESS.md
    ├── ENVIRONMENT_SYNC_STRATEGY.md
    └── CAE_JUPYTERHUB_MIGRATION_ANALYSIS.md
```

---

## Getting Started

### Prerequisites

- OpenTofu 1.6+
- AWS CLI configured
- kubectl
- SOPS (for secrets encryption)
- Helm 3.x

### Quick Start

```bash
# Initialize for an environment
make init ENVIRONMENT=dev

# Preview changes
make plan ENVIRONMENT=dev

# Apply changes
make apply ENVIRONMENT=dev

# Check status
make status ENVIRONMENT=dev
```

### Creating a New Environment

1. Copy an existing environment:
   ```bash
   cp -r environments/dev environments/myenv
   ```

2. Update `terraform.tfvars` with environment-specific settings

3. Create `secrets.yaml` and encrypt with SOPS:
   ```bash
   sops environments/myenv/secrets.yaml
   ```

4. Create backend resources:
   ```bash
   make init ENVIRONMENT=myenv
   ```

---

## Next Steps

1. **For CI/CD Setup**: Follow [GITHUB_ACTIONS_OPENTOFU.md](./GITHUB_ACTIONS_OPENTOFU.md)

2. **For Environment Sync**: Implement Makefile targets from [ENVIRONMENT_SYNC_STRATEGY.md](./ENVIRONMENT_SYNC_STRATEGY.md)

3. **For CAE Migration**: Review [CAE_JUPYTERHUB_MIGRATION_ANALYSIS.md](./CAE_JUPYTERHUB_MIGRATION_ANALYSIS.md) and resolve the questions listed
