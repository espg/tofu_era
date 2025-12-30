# EKS Cluster Access

This document explains how IAM identities (users and roles) are granted access to EKS clusters in this project.

## Overview

Amazon EKS supports two mechanisms for granting cluster access:

1. **EKS Access Entries (API-based)** - AWS-native API for managing access
2. **aws-auth ConfigMap** - Legacy Kubernetes ConfigMap approach

This project uses **both mechanisms** (`API_AND_CONFIG_MAP` mode) to provide robust access:

```
┌─────────────────────┐     ┌──────────────────────────────┐     ┌─────────────────┐
│  IAM Identity       │────▶│  EKS Access Entries (API)    │────▶│  Kubernetes     │
│  (user or role)     │     │  + aws-auth ConfigMap        │     │  RBAC           │
└─────────────────────┘     └──────────────────────────────┘     └─────────────────┘
```

## How It Works

When you run `kubectl` or Terraform's kubernetes provider:

1. Your AWS credentials identify you as an IAM user/role
2. EKS checks **both** Access Entries and aws-auth ConfigMap
3. If found in either, you're granted access
4. Kubernetes RBAC determines what you can do based on associated policies/groups

### Why Both Mechanisms?

Using both solves the **chicken-and-egg problem**:

- On a fresh cluster, Terraform needs to authenticate to apply Kubernetes resources
- The aws-auth ConfigMap doesn't exist yet (it's what Terraform creates)
- API-based access entries are created via AWS API, not Kubernetes API
- The cluster creator automatically gets admin access via `bootstrap_cluster_creator_admin_permissions`

This means:
- **First deployment**: GitHub Actions gets access via bootstrap + Access Entries
- **Subsequent access**: Both API and ConfigMap work
- **No manual intervention needed**: kubectl works immediately after cluster creation

## Configuration

### Variables

In your `terraform.tfvars`:

```hcl
# IAM roles that need cluster access (e.g., CI/CD)
cluster_admin_roles = [
  {
    arn      = "arn:aws:iam::ACCOUNT_ID:role/github-actions-tofu-era"
    username = "github-actions"
  }
]

# IAM users that need cluster access (e.g., developers)
cluster_admin_users = [
  {
    arn      = "arn:aws:iam::ACCOUNT_ID:user/your-username"
    username = "your-username"
  }
]
```

### What Gets Created

**1. EKS Access Entries (in EKS module)**

Created via AWS API - no cluster access needed:

```hcl
# For each entry in cluster_admin_roles and cluster_admin_users:
resource "aws_eks_access_entry" "admin_users" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = "arn:aws:iam::ACCOUNT_ID:user/espg"
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "admin_users" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = "arn:aws:iam::ACCOUNT_ID:user/espg"
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope { type = "cluster" }
}
```

**2. aws-auth ConfigMap (in Kubernetes module)**

Created via Kubernetes API (requires cluster access, which is provided by #1):

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-auth
  namespace: kube-system
data:
  mapRoles: |
    # Node role - required for EC2 nodes to join the cluster
    - rolearn: arn:aws:iam::ACCOUNT_ID:role/jupyterhub-CLUSTER-node-role
      username: system:node:{{EC2PrivateDNSName}}
      groups:
        - system:bootstrappers
        - system:nodes
    # GitHub Actions role
    - rolearn: arn:aws:iam::ACCOUNT_ID:role/github-actions-tofu-era
      username: github-actions
      groups:
        - system:masters
  mapUsers: |
    - userarn: arn:aws:iam::ACCOUNT_ID:user/espg
      username: espg
      groups:
        - system:masters
```

## Common Scenarios

### Adding a New Developer

1. Add their IAM user to `cluster_admin_users` in the environment's `terraform.tfvars`:

   ```hcl
   cluster_admin_users = [
     {
       arn      = "arn:aws:iam::992398409787:user/espg"
       username = "espg"
     },
     {
       arn      = "arn:aws:iam::992398409787:user/new-developer"
       username = "new-developer"
     }
   ]
   ```

2. Apply the changes:
   ```bash
   make apply ENVIRONMENT=cae-dev
   ```

This creates both an Access Entry and ConfigMap entry for the user.

### Setting Up CI/CD Access

1. Create the IAM role for GitHub Actions (see [GITHUB_ACTIONS_OPENTOFU.md](./GITHUB_ACTIONS_OPENTOFU.md))

2. Add the role to `cluster_admin_roles`:

   ```hcl
   cluster_admin_roles = [
     {
       arn      = "arn:aws:iam::992398409787:role/github-actions-tofu-era"
       username = "github-actions"
     }
   ]
   ```

### Debugging Access Issues

If you see `Unauthorized` errors:

1. **Check your IAM identity:**
   ```bash
   aws sts get-caller-identity
   ```

2. **Check Access Entries (preferred):**
   ```bash
   aws eks list-access-entries --cluster-name jupyterhub-cae-dev
   ```

3. **Check the aws-auth ConfigMap:**
   ```bash
   kubectl get configmap aws-auth -n kube-system -o yaml
   ```

4. **Verify your identity is listed** in Access Entries or aws-auth

5. **If missing, add it** to the appropriate variable in `terraform.tfvars` and apply

### View Current Access Configuration

```bash
# List all access entries
aws eks list-access-entries --cluster-name jupyterhub-cae-dev

# Get details for a specific entry
aws eks describe-access-entry \
  --cluster-name jupyterhub-cae-dev \
  --principal-arn arn:aws:iam::992398409787:user/espg

# List associated policies
aws eks list-associated-access-policies \
  --cluster-name jupyterhub-cae-dev \
  --principal-arn arn:aws:iam::992398409787:user/espg
```

## EKS Access Policies

| Policy | Permissions |
|--------|-------------|
| `AmazonEKSClusterAdminPolicy` | Full cluster admin (read/write all resources) |
| `AmazonEKSAdminPolicy` | Admin access to most resources |
| `AmazonEKSEditPolicy` | Read/write access to most resources |
| `AmazonEKSViewPolicy` | Read-only access |

For admin users and CI/CD, we use `AmazonEKSClusterAdminPolicy`.

## Security Considerations

1. **Principle of Least Privilege**: Only add users/roles that truly need cluster access

2. **Use Roles for CI/CD**: IAM roles (assumed via OIDC) are more secure than IAM users with static credentials

3. **Audit Access**:
   - Access Entries are visible via AWS CLI/Console
   - aws-auth ConfigMap is in Terraform state

4. **Cluster Creator Bootstrap**: The IAM identity that creates the cluster gets implicit admin access via `bootstrap_cluster_creator_admin_permissions`. This is tracked in AWS, not the ConfigMap.

## Troubleshooting

### "Unauthorized" from GitHub Actions

The GitHub Actions IAM role isn't in `cluster_admin_roles`. Add it and apply.

### "Unauthorized" from Local kubectl

Your IAM user isn't in `cluster_admin_users`. Add it and apply.

### Nodes Not Joining Cluster

The node IAM role is missing from aws-auth. This is handled automatically—if nodes aren't joining, check the EKS console for node group errors.

### Lost All Access

If you're completely locked out:

1. Use AWS Console → EKS → Cluster → Access tab
2. Create an access entry manually for your IAM user
3. Associate `AmazonEKSClusterAdminPolicy`
4. Or use AWS CLI:
   ```bash
   aws eks create-access-entry \
     --cluster-name jupyterhub-cae-dev \
     --principal-arn arn:aws:iam::ACCOUNT_ID:user/YOUR_USER

   aws eks associate-access-policy \
     --cluster-name jupyterhub-cae-dev \
     --principal-arn arn:aws:iam::ACCOUNT_ID:user/YOUR_USER \
     --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
     --access-scope type=cluster
   ```

## Related Documentation

- [GITHUB_ACTIONS_OPENTOFU.md](./GITHUB_ACTIONS_OPENTOFU.md) - Setting up CI/CD with OIDC
- [AWS EKS Documentation: Access entries](https://docs.aws.amazon.com/eks/latest/userguide/access-entries.html)
- [AWS EKS Documentation: aws-auth ConfigMap](https://docs.aws.amazon.com/eks/latest/userguide/add-user-role.html)
