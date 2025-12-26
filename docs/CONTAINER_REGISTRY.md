# Container Registry Documentation

This document explains the container image strategy for CAE JupyterHub, including the current setup, how to build/push images, and migration paths.

## Current Setup

### Image Location

| Image | Registry | URL |
|-------|----------|-----|
| CAE Notebook | GitHub Container Registry | `ghcr.io/espg/cae-notebook:latest` |
| Base Image | GitHub Container Registry | `ghcr.io/nmfs-opensci/py-rocket-base:2025.12.22` |

### Why ghcr.io?

GitHub Container Registry (ghcr.io) was chosen for initial development because:
- **Free** for public images (no storage/bandwidth costs)
- **Simple auth** - uses GitHub PAT or GITHUB_TOKEN
- **No setup** - just push to create the repo
- **Public pull** - EKS can pull without imagePullSecrets

### Implications of ghcr.io/espg

| Aspect | Details |
|--------|---------|
| **Ownership** | Tied to `espg` GitHub account |
| **Access** | Public read, authenticated write |
| **Risk** | If account deleted/renamed, image URLs break |
| **Cost** | Free for public images |

---

## Building the CAE Image

### Prerequisites

```bash
# Install Docker (or Podman)
# Authenticate to ghcr.io
echo $GITHUB_PAT | docker login ghcr.io -u espg --password-stdin
```

### Build Locally

```bash
cd /home/espg/era/tofu_era/docker

# Build the image
docker build -f Dockerfile.cae -t cae-notebook:test .

# Test locally
docker run -p 8888:8888 cae-notebook:test

# Open http://localhost:8888 and verify:
# 1. Kernel dropdown shows "Python [cae]"
# 2. `import climakitae` works in cae kernel
# 3. VSCode at /vscode works
```

### Push to Registry

```bash
# Tag for ghcr.io
docker tag cae-notebook:test ghcr.io/espg/cae-notebook:latest
docker tag cae-notebook:test ghcr.io/espg/cae-notebook:$(date +%Y.%m.%d)

# Push
docker push ghcr.io/espg/cae-notebook:latest
docker push ghcr.io/espg/cae-notebook:$(date +%Y.%m.%d)
```

### Image Contents

The CAE image includes:

| Component | Source |
|-----------|--------|
| VSCode (code-server) | py-rocket-base |
| RStudio | py-rocket-base |
| Desktop VNC | py-rocket-base |
| Base Python environment | py-rocket-base |
| **CAE kernel** | `environment-cae.yml` |
| Full Pangeo stack | environment-cae.yml |
| climakitae + climakitaegui | environment-cae.yml (pip) |

---

## Migration: Different GitHub Account

To move the image to a different GitHub account (e.g., organization account):

### Step 1: Create New Repository

```bash
# Login to new account
echo $NEW_GITHUB_PAT | docker login ghcr.io -u NEW_ACCOUNT --password-stdin

# Pull existing image
docker pull ghcr.io/espg/cae-notebook:latest

# Retag for new account
docker tag ghcr.io/espg/cae-notebook:latest ghcr.io/NEW_ACCOUNT/cae-notebook:latest

# Push to new location
docker push ghcr.io/NEW_ACCOUNT/cae-notebook:latest
```

### Step 2: Update Terraform

Edit `environments/*/terraform.tfvars`:

```hcl
# Old
singleuser_image_name = "ghcr.io/espg/cae-notebook"

# New
singleuser_image_name = "ghcr.io/NEW_ACCOUNT/cae-notebook"
```

### Step 3: Apply Changes

```bash
make apply ENVIRONMENT=cae-testing
make apply ENVIRONMENT=cae-dev
make apply ENVIRONMENT=cae
```

### Step 4: Update CI/CD (if applicable)

Update `.github/workflows/` to push to new registry location.

---

## Migration: AWS ECR

To move to Amazon Elastic Container Registry for better AWS integration:

### Step 1: Create ECR Repository

```bash
# Set variables
AWS_ACCOUNT=992398409787
AWS_REGION=us-west-2
REPO_NAME=cae-notebook

# Create repository
aws ecr create-repository \
  --repository-name $REPO_NAME \
  --region $AWS_REGION \
  --image-scanning-configuration scanOnPush=true \
  --encryption-configuration encryptionType=AES256

# Get repository URI
ECR_URI=$(aws ecr describe-repositories \
  --repository-names $REPO_NAME \
  --query 'repositories[0].repositoryUri' \
  --output text)
echo "ECR URI: $ECR_URI"
# Output: 992398409787.dkr.ecr.us-west-2.amazonaws.com/cae-notebook
```

### Step 2: Push Image to ECR

```bash
# Login to ECR
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin $AWS_ACCOUNT.dkr.ecr.$AWS_REGION.amazonaws.com

# Pull from ghcr.io
docker pull ghcr.io/espg/cae-notebook:latest

# Retag for ECR
docker tag ghcr.io/espg/cae-notebook:latest $ECR_URI:latest
docker tag ghcr.io/espg/cae-notebook:latest $ECR_URI:$(date +%Y.%m.%d)

# Push to ECR
docker push $ECR_URI:latest
docker push $ECR_URI:$(date +%Y.%m.%d)
```

### Step 3: Update Terraform

Edit `environments/*/terraform.tfvars`:

```hcl
# Old (ghcr.io)
singleuser_image_name = "ghcr.io/espg/cae-notebook"

# New (ECR)
singleuser_image_name = "992398409787.dkr.ecr.us-west-2.amazonaws.com/cae-notebook"
```

### Step 4: Configure EKS Access to ECR

EKS nodes need IAM permissions to pull from ECR. Add to node IAM role:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage"
      ],
      "Resource": "*"
    }
  ]
}
```

**Note**: The EKS module already includes `AmazonEC2ContainerRegistryReadOnly` policy on node roles, so this should work automatically for same-account ECR.

### Step 5: Apply Changes

```bash
make apply ENVIRONMENT=cae-testing
```

### ECR Costs

| Item | Cost |
|------|------|
| Storage | ~$0.10/GB/month |
| Data transfer (same region) | Free |
| Data transfer (cross region) | ~$0.09/GB |

For a ~5GB image: ~$0.50/month storage

### ECR Benefits

| Benefit | Details |
|---------|---------|
| **IAM integration** | No separate credentials needed |
| **Same account** | Lower latency, no cross-account setup |
| **Private** | Images not publicly accessible |
| **Scanning** | Built-in vulnerability scanning |
| **Lifecycle policies** | Auto-delete old images |

---

## CI/CD Integration

### GitHub Actions (ghcr.io)

```yaml
# .github/workflows/build-image.yml
name: Build CAE Image

on:
  push:
    paths:
      - 'docker/**'
    branches:
      - main

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    steps:
      - uses: actions/checkout@v4

      - name: Login to ghcr.io
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build and push
        uses: docker/build-push-action@v5
        with:
          context: ./docker
          file: ./docker/Dockerfile.cae
          push: true
          tags: |
            ghcr.io/${{ github.repository_owner }}/cae-notebook:latest
            ghcr.io/${{ github.repository_owner }}/cae-notebook:${{ github.sha }}
```

### GitHub Actions (ECR)

```yaml
# .github/workflows/build-image-ecr.yml
name: Build CAE Image (ECR)

on:
  push:
    paths:
      - 'docker/**'
    branches:
      - main

env:
  AWS_REGION: us-west-2
  ECR_REPOSITORY: cae-notebook

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read

    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ vars.AWS_ROLE_ARN }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Login to ECR
        id: login-ecr
        uses: aws-actions/amazon-ecr-login@v2

      - name: Build and push
        env:
          ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}
        run: |
          docker build -f docker/Dockerfile.cae -t $ECR_REGISTRY/$ECR_REPOSITORY:latest docker/
          docker push $ECR_REGISTRY/$ECR_REPOSITORY:latest
```

---

## Troubleshooting

### EKS Can't Pull Image

**Symptom**: Pods stuck in `ImagePullBackOff`

**For ghcr.io** (public):
- Verify image exists: `docker pull ghcr.io/espg/cae-notebook:latest`
- Check image name/tag in terraform.tfvars

**For ECR** (private):
- Verify node IAM role has ECR permissions
- Check ECR repository exists in same region as EKS
- Verify image tag exists: `aws ecr list-images --repository-name cae-notebook`

### Image Too Large

**Symptom**: Slow pod startup, disk space issues

**Solutions**:
- Use multi-stage builds to reduce layers
- Remove build dependencies after install
- Use `mamba clean --all -f -y` after conda installs
- Consider splitting into multiple images

### Environment Conflicts

**Symptom**: Package import errors in cae kernel

**Solutions**:
- Pin package versions in `environment-cae.yml`
- Check for conflicts: `mamba run -n cae conda list`
- Rebuild image with updated dependencies

---

## Version History

| Date | Version | Changes |
|------|---------|---------|
| 2025-12-26 | Initial | Created CAE image based on py-rocket-base:2025.12.22 |

---

## Related Files

- `docker/Dockerfile.cae` - Image build definition
- `docker/environment-cae.yml` - CAE conda environment specification
- `environments/*/terraform.tfvars` - Image configuration per environment
