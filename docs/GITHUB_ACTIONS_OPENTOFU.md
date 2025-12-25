# GitHub Actions for OpenTofu CI/CD

This document outlines how to set up GitHub Actions to automatically trigger OpenTofu (tofu) builds as part of git commits and pull requests.

## Table of Contents
1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [AWS Authentication Methods](#aws-authentication-methods)
4. [Workflow Files](#workflow-files)
5. [Environment Protection Rules](#environment-protection-rules)
6. [Secrets Management](#secrets-management)
7. [State Locking Considerations](#state-locking-considerations)
8. [Implementation Steps](#implementation-steps)

---

## Overview

### How It Works

GitHub Actions can run OpenTofu commands (`tofu plan`, `tofu apply`) in response to:
- **Pull Requests**: Run `tofu plan` to preview changes
- **Pushes to main**: Run `tofu apply` to deploy changes (with approval gates)
- **Manual triggers**: Allow on-demand deployments via `workflow_dispatch`

### Workflow Summary

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  Developer      │────▶│  GitHub Actions │────▶│  AWS            │
│  pushes code    │     │  runs tofu      │     │  infrastructure │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                               │
                        ┌──────┴──────┐
                        │  OpenTofu   │
                        │  State in   │
                        │  S3 + DDB   │
                        └─────────────┘
```

---

## Prerequisites

### Required Components

1. **OpenTofu Configuration** (already present in this repo)
   - `main.tf`, `variables.tf`, `outputs.tf`
   - `environments/*/terraform.tfvars` for each environment
   - `environments/*/backend.tfvars` for state configuration

2. **AWS Resources for State**
   - S3 bucket for OpenTofu state
   - DynamoDB table for state locking
   - KMS key for state encryption (optional but recommended)

3. **GitHub Repository Secrets** (configured in GitHub → Settings → Secrets)
   - AWS credentials or OIDC configuration
   - SOPS age key or AWS KMS access for secrets decryption

4. **GitHub Environments** (for approval workflows)
   - `dev`, `staging`, `prod` environments with appropriate protection rules

---

## AWS Authentication Methods

### Option A: OIDC (Recommended - No Long-Lived Credentials)

OIDC federation allows GitHub Actions to assume an AWS IAM role without storing AWS credentials as secrets. This is the **recommended approach** for security.

#### Step 1: Create OIDC Identity Provider in AWS

```bash
# Create the OIDC provider
aws iam create-open-id-connect-provider \
  --url "https://token.actions.githubusercontent.com" \
  --client-id-list "sts.amazonaws.com" \
  --thumbprint-list "6938fd4d98bab03faadb97b34396831e3780aea1"
```

Or via OpenTofu:

```hcl
# Add to your AWS account setup (not the EKS cluster)
resource "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}
```

#### Step 2: Create IAM Role for GitHub Actions

```hcl
data "aws_iam_policy_document" "github_actions_trust" {
  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      # Replace with your GitHub org/repo
      values   = ["repo:YOUR_ORG/tofu_era:*"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "github-actions-opentofu"
  assume_role_policy = data.aws_iam_policy_document.github_actions_trust.json
}

# Attach necessary permissions
resource "aws_iam_role_policy_attachment" "github_actions_admin" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"  # Scope down in production!
}
```

#### Step 3: Store Role ARN in GitHub

Add to GitHub Repository Settings → Secrets and variables → Actions:
- **Variable**: `AWS_ROLE_ARN` = `arn:aws:iam::ACCOUNT_ID:role/github-actions-opentofu`
- **Variable**: `AWS_REGION` = `us-west-2`

### Option B: IAM Access Keys (Less Secure, Simpler Setup)

If OIDC is not feasible, you can use IAM access keys stored as GitHub secrets.

#### Create IAM User and Keys

```bash
# Create user
aws iam create-user --user-name github-actions-tofu

# Attach policy
aws iam attach-user-policy \
  --user-name github-actions-tofu \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess  # Scope down!

# Create access keys
aws iam create-access-key --user-name github-actions-tofu
```

#### Store in GitHub Secrets

Add to GitHub Repository Settings → Secrets:
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

**Warning**: Long-lived credentials require rotation and pose a security risk if leaked.

---

## Workflow Files

### Primary Workflow: `.github/workflows/tofu.yml`

```yaml
name: OpenTofu CI/CD

on:
  push:
    branches:
      - main
    paths:
      - '*.tf'
      - 'modules/**'
      - 'environments/**'
      - '.github/workflows/tofu.yml'
  pull_request:
    branches:
      - main
    paths:
      - '*.tf'
      - 'modules/**'
      - 'environments/**'
  workflow_dispatch:
    inputs:
      environment:
        description: 'Environment to deploy'
        required: true
        default: 'dev'
        type: choice
        options:
          - dev
          - staging
          - englacial
          - prod
      action:
        description: 'Action to perform'
        required: true
        default: 'plan'
        type: choice
        options:
          - plan
          - apply
          - destroy

env:
  TOFU_VERSION: '1.6.0'
  AWS_REGION: 'us-west-2'

permissions:
  id-token: write   # Required for OIDC
  contents: read
  pull-requests: write  # For PR comments

jobs:
  # Determine which environments changed
  detect-changes:
    runs-on: ubuntu-latest
    outputs:
      environments: ${{ steps.changes.outputs.environments }}
      matrix: ${{ steps.matrix.outputs.matrix }}
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Detect changed environments
        id: changes
        run: |
          if [ "${{ github.event_name }}" == "workflow_dispatch" ]; then
            echo "environments=${{ github.event.inputs.environment }}" >> $GITHUB_OUTPUT
          else
            # Check which environment files changed
            CHANGED=$(git diff --name-only ${{ github.event.before }} ${{ github.sha }} | \
              grep -E '^environments/[^/]+/' | \
              sed 's|environments/||' | \
              cut -d/ -f1 | \
              sort -u | \
              tr '\n' ',' | \
              sed 's/,$//')

            # If no specific env changed but core files did, run on dev
            if [ -z "$CHANGED" ]; then
              CORE_CHANGED=$(git diff --name-only ${{ github.event.before }} ${{ github.sha }} | \
                grep -E '^(main\.tf|variables\.tf|outputs\.tf|modules/)' | wc -l)
              if [ "$CORE_CHANGED" -gt 0 ]; then
                CHANGED="dev"
              fi
            fi

            echo "environments=$CHANGED" >> $GITHUB_OUTPUT
          fi

      - name: Create matrix
        id: matrix
        run: |
          ENVS="${{ steps.changes.outputs.environments }}"
          if [ -n "$ENVS" ]; then
            MATRIX=$(echo "$ENVS" | tr ',' '\n' | jq -R . | jq -s '{environment: .}')
            echo "matrix=$MATRIX" >> $GITHUB_OUTPUT
          else
            echo "matrix={\"environment\":[]}" >> $GITHUB_OUTPUT
          fi

  # Run OpenTofu plan
  plan:
    needs: detect-changes
    if: needs.detect-changes.outputs.environments != ''
    runs-on: ubuntu-latest
    strategy:
      matrix: ${{ fromJson(needs.detect-changes.outputs.matrix) }}
      fail-fast: false
    environment: ${{ matrix.environment }}

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup OpenTofu
        uses: opentofu/setup-opentofu@v1
        with:
          tofu_version: ${{ env.TOFU_VERSION }}

      - name: Configure AWS credentials (OIDC)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ vars.AWS_ROLE_ARN }}
          aws-region: ${{ env.AWS_REGION }}
          role-session-name: github-actions-tofu

      - name: Setup SOPS
        uses: mdgreenwald/mozilla-sops-action@v1.6.0

      - name: Initialize OpenTofu
        run: |
          tofu init -backend-config=environments/${{ matrix.environment }}/backend.tfvars

      - name: Plan
        id: plan
        run: |
          tofu plan \
            -var-file=environments/${{ matrix.environment }}/terraform.tfvars \
            -out=tfplan-${{ matrix.environment }} \
            -no-color 2>&1 | tee plan_output.txt
        continue-on-error: true

      - name: Upload plan
        uses: actions/upload-artifact@v4
        with:
          name: tfplan-${{ matrix.environment }}
          path: tfplan-${{ matrix.environment }}
          retention-days: 5

      - name: Comment on PR
        if: github.event_name == 'pull_request'
        uses: actions/github-script@v7
        with:
          script: |
            const fs = require('fs');
            const plan = fs.readFileSync('plan_output.txt', 'utf8');
            const output = `## OpenTofu Plan - \`${{ matrix.environment }}\`

            <details><summary>Show Plan</summary>

            \`\`\`hcl
            ${plan.slice(0, 60000)}
            \`\`\`

            </details>

            *Pushed by: @${{ github.actor }}, Action: \`${{ github.event_name }}\`*`;

            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: output
            });

      - name: Plan Status
        if: steps.plan.outcome == 'failure'
        run: exit 1

  # Apply changes (only on main branch push or manual trigger)
  apply:
    needs: [detect-changes, plan]
    if: |
      (github.event_name == 'push' && github.ref == 'refs/heads/main') ||
      (github.event_name == 'workflow_dispatch' && github.event.inputs.action == 'apply')
    runs-on: ubuntu-latest
    strategy:
      matrix: ${{ fromJson(needs.detect-changes.outputs.matrix) }}
      max-parallel: 1  # Apply one environment at a time
    environment:
      name: ${{ matrix.environment }}
      url: ${{ steps.output.outputs.jupyterhub_url }}

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup OpenTofu
        uses: opentofu/setup-opentofu@v1
        with:
          tofu_version: ${{ env.TOFU_VERSION }}

      - name: Configure AWS credentials (OIDC)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ vars.AWS_ROLE_ARN }}
          aws-region: ${{ env.AWS_REGION }}
          role-session-name: github-actions-tofu

      - name: Setup SOPS
        uses: mdgreenwald/mozilla-sops-action@v1.6.0

      - name: Download plan
        uses: actions/download-artifact@v4
        with:
          name: tfplan-${{ matrix.environment }}

      - name: Initialize OpenTofu
        run: |
          tofu init -backend-config=environments/${{ matrix.environment }}/backend.tfvars

      - name: Apply
        run: |
          tofu apply -auto-approve tfplan-${{ matrix.environment }}

      - name: Get outputs
        id: output
        run: |
          URL=$(tofu output -raw jupyterhub_url 2>/dev/null || echo "N/A")
          echo "jupyterhub_url=$URL" >> $GITHUB_OUTPUT
```

### Destroy Workflow: `.github/workflows/tofu-destroy.yml`

For safety, keep destroy in a separate workflow with extra confirmations:

```yaml
name: OpenTofu Destroy

on:
  workflow_dispatch:
    inputs:
      environment:
        description: 'Environment to destroy'
        required: true
        type: choice
        options:
          - dev
          - staging
      confirm:
        description: 'Type environment name to confirm'
        required: true

env:
  TOFU_VERSION: '1.6.0'
  AWS_REGION: 'us-west-2'

permissions:
  id-token: write
  contents: read

jobs:
  destroy:
    runs-on: ubuntu-latest
    if: github.event.inputs.confirm == github.event.inputs.environment
    environment: ${{ github.event.inputs.environment }}

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup OpenTofu
        uses: opentofu/setup-opentofu@v1
        with:
          tofu_version: ${{ env.TOFU_VERSION }}

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ vars.AWS_ROLE_ARN }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Initialize
        run: |
          tofu init -backend-config=environments/${{ github.event.inputs.environment }}/backend.tfvars

      - name: Destroy
        run: |
          tofu destroy \
            -var-file=environments/${{ github.event.inputs.environment }}/terraform.tfvars \
            -auto-approve
```

---

## Environment Protection Rules

Configure environment protection in GitHub Repository Settings → Environments:

### Development Environment
- **No protection**: Auto-deploy on push

### Staging Environment
- **Required reviewers**: 1 reviewer from team
- **Wait timer**: 5 minutes (allow cancellation)

### Production Environment
- **Required reviewers**: 2 reviewers
- **Wait timer**: 15 minutes
- **Deployment branches**: Only `main`
- **Environment secrets**: Separate production credentials (if using IAM keys)

---

## Secrets Management

### SOPS Integration

The project uses SOPS for encrypting `secrets.yaml` files. For GitHub Actions to decrypt:

#### Option 1: AWS KMS (Recommended with OIDC)

If SOPS is configured to use AWS KMS keys, the OIDC role needs KMS permissions:

```hcl
# Add to GitHub Actions role policy
{
  "Effect": "Allow",
  "Action": [
    "kms:Decrypt",
    "kms:DescribeKey"
  ],
  "Resource": "arn:aws:kms:us-west-2:ACCOUNT:key/KEY_ID"
}
```

#### Option 2: Age Key

Store the age private key as a GitHub secret:

1. Add secret `SOPS_AGE_KEY` with the private key content
2. In workflow, export before running tofu:

```yaml
- name: Setup SOPS
  env:
    SOPS_AGE_KEY: ${{ secrets.SOPS_AGE_KEY }}
  run: |
    echo "$SOPS_AGE_KEY" > /tmp/age-key.txt
    export SOPS_AGE_KEY_FILE=/tmp/age-key.txt
```

---

## State Locking Considerations

### DynamoDB Lock Table

The existing backend configuration uses DynamoDB for state locking. Ensure the GitHub Actions role has permissions:

```json
{
  "Effect": "Allow",
  "Action": [
    "dynamodb:GetItem",
    "dynamodb:PutItem",
    "dynamodb:DeleteItem"
  ],
  "Resource": "arn:aws:dynamodb:us-west-2:ACCOUNT:table/terraform-state-lock"
}
```

### Handling Lock Conflicts

If a local `tofu apply` is running when GitHub Actions tries to apply:
- The action will fail with a lock error
- This is expected behavior - prevents concurrent modifications
- Wait for local operation to complete, then re-run workflow

---

## Implementation Steps

### Step 1: Set Up AWS OIDC Provider

```bash
# Run from your AWS account (not the EKS cluster)
aws iam create-open-id-connect-provider \
  --url "https://token.actions.githubusercontent.com" \
  --client-id-list "sts.amazonaws.com" \
  --thumbprint-list "6938fd4d98bab03faadb97b34396831e3780aea1"
```

### Step 2: Create IAM Role

Use the OpenTofu configuration in the "AWS Authentication Methods" section, or create manually:

```bash
# Create trust policy
cat > trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:YOUR_ORG/tofu_era:*"
        }
      }
    }
  ]
}
EOF

aws iam create-role \
  --role-name github-actions-opentofu \
  --assume-role-policy-document file://trust-policy.json

aws iam attach-role-policy \
  --role-name github-actions-opentofu \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

### Step 3: Configure GitHub Repository

1. Go to repository Settings → Secrets and variables → Actions
2. Add **Variable** (not secret): `AWS_ROLE_ARN` = role ARN from step 2
3. Add **Variable**: `AWS_REGION` = `us-west-2`

### Step 4: Create GitHub Environments

1. Go to repository Settings → Environments
2. Create: `dev`, `staging`, `prod`
3. For `prod`:
   - Add required reviewers
   - Add deployment branch rule: `main`

### Step 5: Add Workflow Files

Copy the workflow files from this document to your repository:

```bash
mkdir -p .github/workflows
# Create tofu.yml and tofu-destroy.yml as shown above
```

### Step 6: Test the Workflow

1. Create a PR with a minor change (e.g., add a comment to `main.tf`)
2. Verify `tofu plan` runs and posts comment to PR
3. Merge PR and verify `tofu apply` runs with approval

---

## Best Practices

### 1. Never Auto-Apply to Production

Always require manual approval for production deployments.

### 2. Use Branch Protection

Require PR reviews before merging to `main`.

### 3. Limit Workflow Permissions

Use minimal IAM permissions. The example uses `AdministratorAccess` for simplicity, but you should scope this down:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "eks:*",
        "ec2:*",
        "iam:*",
        "s3:*",
        "kms:*",
        "elasticloadbalancing:*",
        "autoscaling:*",
        "acm:*"
      ],
      "Resource": "*"
    }
  ]
}
```

### 4. Use Plan Artifacts

Always save plan files as artifacts and apply from them, not by re-running `tofu plan`.

### 5. Monitor Runs

Set up Slack/email notifications for failed runs using GitHub Actions notifications.

---

## Troubleshooting

### "Error assuming role"

- Verify OIDC provider thumbprint
- Check trust policy conditions match your repo
- Ensure `id-token: write` permission is set

### "State locked"

- Check for running local operations
- Use `tofu force-unlock` if necessary (with caution)

### "SOPS decryption failed"

- Verify KMS permissions or age key setup
- Check `.sops.yaml` configuration matches environment

### "Plan shows unexpected changes"

- Ensure you're using the correct `backend.tfvars`
- Check for state drift (someone applied manually)
- Run `tofu refresh` to sync state
