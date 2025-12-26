# EKS Cluster Access (aws-auth ConfigMap)

This document explains how IAM identities (users and roles) are granted access to EKS clusters in this project.

## Overview

Amazon EKS uses the `aws-auth` ConfigMap in the `kube-system` namespace to map AWS IAM identities to Kubernetes RBAC permissions. Without an entry in this ConfigMap, an IAM identity cannot interact with the cluster—even if it has full AWS permissions.

## How It Works

```
┌─────────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  IAM Identity       │────▶│  aws-auth        │────▶│  Kubernetes     │
│  (user or role)     │     │  ConfigMap       │     │  RBAC           │
└─────────────────────┘     └──────────────────┘     └─────────────────┘
         │                          │                        │
         │                          │                        │
    "Who am I?"              "Map to K8s user"         "What can I do?"
```

When you run `kubectl` or Terraform's kubernetes provider:

1. Your AWS credentials identify you as an IAM user/role
2. EKS checks the `aws-auth` ConfigMap for a matching entry
3. If found, you're mapped to a Kubernetes user with specific group memberships
4. Kubernetes RBAC determines what you can do based on those groups

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

The kubernetes module generates the `aws-auth` ConfigMap:

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
    # GitHub Actions role - for CI/CD
    - rolearn: arn:aws:iam::ACCOUNT_ID:role/github-actions-tofu-era
      username: github-actions
      groups:
        - system:masters
  mapUsers: |
    # Developer access
    - userarn: arn:aws:iam::ACCOUNT_ID:user/your-username
      username: your-username
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

2. **Check the aws-auth ConfigMap:**
   ```bash
   kubectl get configmap aws-auth -n kube-system -o yaml
   ```

3. **Verify your identity is listed** in either `mapRoles` or `mapUsers`

4. **If missing, add it** to the appropriate variable in `terraform.tfvars` and apply

### Manual Emergency Fix

If you're locked out and can't run Terraform, patch the ConfigMap directly:

```bash
kubectl patch configmap aws-auth -n kube-system --type merge -p '
{
  "data": {
    "mapUsers": "- userarn: arn:aws:iam::ACCOUNT_ID:user/YOUR_USER\n  username: YOUR_USER\n  groups:\n  - system:masters\n"
  }
}'
```

**Note:** This requires you to have some form of cluster access (e.g., as the cluster creator, who gets implicit access).

## Kubernetes RBAC Groups

| Group | Permissions |
|-------|-------------|
| `system:masters` | Full cluster admin (like root) |
| `system:nodes` | Permissions for kubelet on nodes |
| `system:bootstrappers` | Permissions for node bootstrap process |

For most admin users and CI/CD roles, `system:masters` is appropriate.

## Security Considerations

1. **Principle of Least Privilege**: Only add users/roles that truly need cluster access

2. **Use Roles for CI/CD**: IAM roles (assumed via OIDC) are more secure than IAM users with static credentials

3. **Audit Access**: The `aws-auth` ConfigMap is visible in Git via Terraform, making access auditable

4. **Cluster Creator**: The IAM identity that creates the cluster gets implicit admin access, but this isn't visible in `aws-auth`. Always add explicit entries for reliability.

## Troubleshooting

### "Unauthorized" from GitHub Actions

The GitHub Actions IAM role isn't in `cluster_admin_roles`. Add it and apply.

### "Unauthorized" from Local kubectl

Your IAM user isn't in `cluster_admin_users`. Add it and apply.

### Nodes Not Joining Cluster

The node IAM role is missing or incorrect. Check that `node_role_arn` is passed correctly to the kubernetes module. This is handled automatically—if nodes aren't joining, check the EKS console for node group errors.

### Lost All Access

If you're completely locked out:

1. Use AWS Console to access EKS
2. Go to the cluster → Configuration → Compute → Access
3. Or use `aws eks update-kubeconfig` as the cluster creator (implicit access)
4. Patch the `aws-auth` ConfigMap manually

## Related Documentation

- [GITHUB_ACTIONS_OPENTOFU.md](./GITHUB_ACTIONS_OPENTOFU.md) - Setting up CI/CD with OIDC
- [AWS EKS Documentation: Managing users and roles](https://docs.aws.amazon.com/eks/latest/userguide/add-user-role.html)
