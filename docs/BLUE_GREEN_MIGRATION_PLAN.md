# CAE JupyterHub Blue/Green Migration Plan

## Overview

This document outlines the blue/green deployment strategy for migrating CAE JupyterHub from the existing `cae-jupyterhub` (eksctl + Helm) deployment to the new `tofu_era` (OpenTofu) deployment.

### Terminology
- **Blue (Current)**: Existing deployment at `hub.cal-adapt.org` (cae-jupyterhub repo)
- **Green (New)**: New deployment using tofu_era infrastructure

### Key Benefits
- Zero-downtime migration
- Easy rollback if issues arise
- Users can validate new environment before cutover
- Shared Cognito authentication (no re-enrollment needed)
- Shared S3 scratch bucket (users keep their data)

---

## Timeline

### Week 1: Setup (This Week)

| Day | Task |
|-----|------|
| Day 1-2 | Deploy cae-dev environment for testing |
| Day 2-3 | Test lifecycle hooks, profile selection, Dask workers |
| Day 3-4 | Deploy Green (new) CAE production cluster |
| Day 4-5 | Configure DNS: Green at `new-hub.cal-adapt.org` (temporary) |
| Day 5 | Validate Green environment with test users |

### Week 2: Migration

| Day | Task |
|-----|------|
| Day 1 | Send user communication about migration |
| Day 2-3 | Parallel running: Users can access both environments |
| Day 3 | Final validation, address any user-reported issues |
| Day 4 | **DNS Cutover** (detailed below) |
| Day 5 | Monitor, deprecate Blue environment |

---

## Prerequisites

### Before Starting

1. **AWS CLI configured** for both accounts:
   - Production (390197508439)
   - Development (992398409787)

2. **SOPS encryption key** created in production account:
   ```bash
   aws kms create-alias \
     --alias-name alias/sops-jupyterhub-cae-usw2 \
     --target-key-id <KMS_KEY_ID>
   ```

3. **Cognito client secret** retrieved from existing user pool:
   - AWS Console → Cognito → User Pools → cae → App clients
   - Client ID: `3jesa7vt6hanjscanmj93cj2kg`

4. **DNS access** for `cal-adapt.org` domain

5. **ACM certificate** for `*.cal-adapt.org` (or validate new cert)

---

## Quick Commands Reference

### Check Active Users

Before any migration step, verify no users are logged in:

```bash
# Quick one-liner - shows active user pods
kubectl get pods -n daskhub -l component=singleuser-server \
  -o custom-columns=USER:.metadata.labels.'hub\.jupyter\.org/username',STATUS:.status.phase,AGE:.metadata.creationTimestamp

# Full script with safety checks (exits non-zero if users active)
./scripts/check-active-users.sh daskhub
```

### Get Load Balancer Address

```bash
# Get the NLB hostname for DNS configuration
kubectl get svc -n daskhub proxy-public \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

---

## Detailed Steps

### Phase 1: Development Environment Testing

```bash
# 1. Switch to dev account
aws configure --profile cae-dev

# 2. Create backend infrastructure
cd /home/espg/era/tofu_era
make bootstrap ENVIRONMENT=cae-dev AWS_PROFILE=cae-dev

# 3. Create and encrypt secrets
cp environments/cae-dev/secrets.yaml.example environments/cae-dev/secrets.yaml
# Edit with GitHub OAuth credentials
sops --encrypt --in-place environments/cae-dev/secrets.yaml

# 4. Initialize and deploy
make init ENVIRONMENT=cae-dev
make plan ENVIRONMENT=cae-dev
make apply ENVIRONMENT=cae-dev

# 5. Test
# - Profile selection works
# - Dask workers scale correctly (1-4 cores)
# - Lifecycle hooks install climakitae
# - gitpuller fetches cae-notebooks
```

### Phase 2: Green Production Deployment

```bash
# 1. Switch to production account
aws configure --profile cae

# 2. Create backend infrastructure
make bootstrap ENVIRONMENT=cae AWS_PROFILE=cae

# 3. Create and encrypt secrets
cp environments/cae/secrets.yaml.example environments/cae/secrets.yaml
# Add Cognito client secret from existing user pool
sops --encrypt --in-place environments/cae/secrets.yaml

# 4. Initialize and deploy
make init ENVIRONMENT=cae
make plan ENVIRONMENT=cae
make apply ENVIRONMENT=cae

# 5. Get load balancer hostname
kubectl get svc -n jupyterhub proxy-public -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

### Phase 3: Temporary DNS Setup

Create a temporary DNS record for Green environment:

```
new-hub.cal-adapt.org  →  <GREEN_LOAD_BALANCER>
```

**Note**: The ACM certificate should already support `*.cal-adapt.org` or you'll need to add `new-hub.cal-adapt.org` to the certificate.

### Phase 4: Parallel Running Validation

Both environments accessible:
- **Blue**: `hub.cal-adapt.org` (existing)
- **Green**: `new-hub.cal-adapt.org` (new)

Validation checklist:
- [ ] Users can login via Cognito
- [ ] Profile selection (Small/Medium) works
- [ ] Notebooks start successfully
- [ ] S3 scratch data accessible (`s3://cadcat-tmp/<user>`)
- [ ] Dask clusters create successfully
- [ ] Dask workers scale up (test 1-4 cores per worker)
- [ ] climakitae imports without errors
- [ ] cae-notebooks pulled correctly
- [ ] WebSocket connections stable (no 504 errors)

---

## DNS Cutover Procedure

### Pre-Cutover Checklist

- [ ] Green environment fully validated
- [ ] User communication sent (24+ hours notice)
- [ ] Rollback plan reviewed by team
- [ ] On-call support scheduled for cutover window

### Cutover Steps

**Timing**: Recommend early morning or low-usage period

1. **Notify active users** (if any):
   ```
   JupyterHub will be briefly unavailable in 15 minutes for DNS migration.
   Your work is saved. Please save any unsaved notebooks.
   ```

2. **Update DNS records** (order matters):

   | Record | Old Value | New Value |
   |--------|-----------|-----------|
   | `legacy.cal-adapt.org` | (new) | `<BLUE_LOAD_BALANCER>` |
   | `hub.cal-adapt.org` | `<BLUE_LOAD_BALANCER>` | `<GREEN_LOAD_BALANCER>` |

3. **Update Blue Cognito callback** (in AWS Console):
   - Change callback URL from `hub.cal-adapt.org` to `legacy.cal-adapt.org`
   - Update logout redirect URL

4. **Wait for DNS propagation** (5-15 minutes):
   ```bash
   # Check propagation
   dig hub.cal-adapt.org +short
   # Should show GREEN load balancer
   ```

5. **Verify Green is serving traffic**:
   ```bash
   curl -I https://hub.cal-adapt.org/hub/health
   ```

6. **Update Green callback URLs** if needed (should already be correct):
   - Cognito callback: `https://hub.cal-adapt.org/hub/oauth_callback`
   - Logout redirect: `https://hub.cal-adapt.org`

### Post-Cutover

1. **Monitor for 24-48 hours**:
   - User login success rate
   - Pod startup times
   - Dask cluster creation
   - WebSocket stability

2. **Keep Blue running** for 1 week (rollback safety)

3. **Remove temporary DNS**:
   - Delete `new-hub.cal-adapt.org` record

---

## Rollback Plan

### If Issues Arise After Cutover

**Immediate rollback** (< 2 hours from cutover):

1. **Revert DNS**:
   | Record | Current | Rollback |
   |--------|---------|----------|
   | `hub.cal-adapt.org` | `<GREEN>` | `<BLUE>` |

2. **Revert Cognito callback** to `hub.cal-adapt.org`

3. **Investigate issues** on Green while Blue serves traffic

### If Issues Arise After 24+ Hours

Users may have created new data in Green. Options:

1. **Fix forward**: Debug and fix Green issues
2. **Partial rollback**: Keep Green running, route specific users to Blue
3. **Full rollback with data migration**: Sync any new S3 data from Green user pods

---

## User Communication Templates

### Pre-Migration Notice (1 week before)

```
Subject: CAE JupyterHub Upgrade - Week of [DATE]

Dear CAE Users,

We're upgrading the Cal-Adapt Analytics Engine JupyterHub to a new
infrastructure platform. This upgrade brings:

- Faster pod startup times
- Better stability (improved WebSocket handling)
- Choice of notebook size (Small or Medium) at login
- Enhanced Dask worker scaling

What you need to know:
- Your login credentials remain the same (AWS Cognito)
- Your scratch data (s3://cadcat-tmp) will be preserved
- There will be a brief (~15 minute) transition period on [DATE]

No action is required from you. We'll send another notice before the transition.

Questions? Contact [SUPPORT_EMAIL]
```

### Cutover Day Notice

```
Subject: CAE JupyterHub - Upgrade in Progress

The JupyterHub upgrade is happening now.

- If you're currently logged in, please save your work
- The hub will be briefly unavailable (~15 minutes)
- When you log back in, you'll see a new interface

New features:
- At login, choose "Small" (2 CPU) or "Medium" (4 CPU) notebook
- Improved stability for long-running operations

If you experience any issues, please report them to [SUPPORT_EMAIL]
```

---

## Storage Migration: gp2 to gp3

### Overview

The Blue (old) cluster uses **gp2** EBS volumes for user home directories. The Green (new) cluster uses **gp3** volumes, which offer:

| Aspect | gp2 (Blue) | gp3 (Green) |
|--------|------------|-------------|
| **IOPS** | 3 IOPS/GB (scales with size) | 3000 IOPS baseline (any size) |
| **Throughput** | 128 MB/s max | 125 MB/s baseline |
| **Cost** | ~$0.10/GB/month | ~$0.08/GB/month (20% cheaper) |
| **Small Volume Performance** | Poor (10GB = 30 IOPS) | Excellent (10GB = 3000 IOPS) |

### User Data Locations

| Data Type | Location | Migration Required? |
|-----------|----------|---------------------|
| S3 scratch data | `s3://cadcat-tmp/{user}` | **No** - same bucket, preserved |
| Home directory | EBS PVC `/home/jovyan` | **Yes** - new PVC on Green |
| Notebooks (cae-notebooks) | Git-pulled at startup | **No** - auto-pulled |
| climakitae | Installed at startup or in image | **No** - auto-installed |

### Migration Approach: Fresh Start with S3 Preservation

**Recommended approach**: Users get fresh home directories on Green, but their S3 scratch data is preserved.

**Why this works for CAE**:
1. S3 (`cadcat-tmp/{user}`) is the primary data store for large datasets
2. Home directories mainly contain notebooks (git-versioned) and cache files
3. Users can copy important files to S3 before migration

### Pre-Migration: User Data Backup

**1 week before cutover**, send instructions to users:

```
Subject: CAE JupyterHub Migration - Please Back Up Your Data

Dear CAE Users,

We're migrating to a new JupyterHub infrastructure on [DATE]. Your S3 scratch
data (s3://cadcat-tmp/your-username) will be preserved automatically.

However, files in your home directory (/home/jovyan) will NOT be migrated.
Please back up any important files before [DATE - 2 days]:

Option 1: Copy to S3 (recommended)
  import s3fs
  fs = s3fs.S3FileSystem()
  fs.put('/home/jovyan/my_notebook.ipynb', 's3://cadcat-tmp/YOUR_USERNAME/backup/')

Option 2: Download locally
  - Right-click files in JupyterLab → Download

Files that do NOT need backup:
- cae-notebooks/ (auto-pulled from GitHub)
- .cache/ directories
- __pycache__/ directories
```

### Alternative: Full PVC Migration (If Required)

If users have significant data in home directories that must be preserved:

#### Step 1: Identify PVCs to Migrate

```bash
# On Blue cluster
kubectl get pvc -n daskhub -o json | jq -r '.items[] | select(.metadata.name | startswith("claim-")) | "\(.metadata.name)\t\(.spec.resources.requests.storage)"'
```

#### Step 2: Snapshot Blue PVCs

```bash
# For each user PVC
USER_PVC="claim-username"
VOLUME_ID=$(kubectl get pv $(kubectl get pvc $USER_PVC -n daskhub -o jsonpath='{.spec.volumeName}') -o jsonpath='{.spec.awsElasticBlockStore.volumeID}' | cut -d'/' -f4)

aws ec2 create-snapshot \
  --volume-id $VOLUME_ID \
  --description "CAE migration: $USER_PVC" \
  --tag-specifications "ResourceType=snapshot,Tags=[{Key=User,Value=$USER_PVC}]"
```

#### Step 3: Create gp3 Volumes from Snapshots

```bash
SNAPSHOT_ID="snap-xxxxx"
aws ec2 create-volume \
  --availability-zone us-west-2a \
  --snapshot-id $SNAPSHOT_ID \
  --volume-type gp3 \
  --iops 3000 \
  --throughput 125 \
  --tag-specifications "ResourceType=volume,Tags=[{Key=Name,Value=cae-migration-$USER_PVC}]"
```

#### Step 4: Import to Green Cluster

```bash
# Create PV pointing to migrated volume
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-migrated-$USERNAME
spec:
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: gp3
  awsElasticBlockStore:
    volumeID: aws://us-west-2a/vol-xxxxx
    fsType: ext4
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: topology.kubernetes.io/zone
          operator: In
          values:
          - us-west-2a
EOF
```

### Storage Class Configuration

Ensure Green cluster has gp3 as default:

```yaml
# Configured in tofu_era EKS module
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  iops: "3000"
  throughput: "125"
  encrypted: "true"
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
```

---

## Architecture Comparison

### Blue (Current)

```
2-Node Architecture (cae-jupyterhub):
├── main2 (r5n.xlarge, on-demand, 1-30 nodes)
│   ├── JupyterHub Hub
│   ├── JupyterHub Proxy
│   ├── User Notebooks (compete with Hub!)
│   └── Dask Gateway
└── dask-workers (m5.*, spot, 1-30 nodes)
    └── Dask Workers

Storage: gp2 EBS volumes
```

### Green (New)

```
3-Node Architecture (tofu_era):
├── system (r5.large, on-demand, 1 node fixed)
│   ├── JupyterHub Hub
│   ├── JupyterHub Proxy
│   └── Dask Gateway
├── user (r5.large/xlarge, on-demand, 0-30 nodes)
│   └── User Notebooks (isolated!)
└── dask (m5.*/m5a.*, spot, 0-30 nodes)
    └── Dask Workers

Storage: gp3 EBS volumes (faster, cheaper)
```

---

## Contacts

| Role | Contact |
|------|---------|
| Platform Lead | mark.koenig@eaglerockanalytics.com |
| DevOps | neil.schroeder@eaglerockanalytics.com |

---

## Appendix: Quick Reference Commands

```bash
# Deploy cae-dev
make apply ENVIRONMENT=cae-dev

# Deploy cae production
make apply ENVIRONMENT=cae

# Get kubeconfig
aws eks update-kubeconfig --name jupyterhub-cae --region us-west-2

# Check pods
kubectl get pods -n jupyterhub

# View hub logs
kubectl logs -n jupyterhub deploy/hub

# Check load balancer
kubectl get svc -n jupyterhub proxy-public

# Force user pod restart (if needed)
kubectl delete pod -n jupyterhub jupyter-<username>
```
