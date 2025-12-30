#!/bin/bash
# migrate-pvcs-ebs-snapshot.sh
#
# Option 1: EBS Snapshot-based PVC Migration (gp2 → gp3)
#
# This script:
# 1. Collects all user PVCs from Blue cluster
# 2. Creates EBS snapshots of each volume
# 3. Creates new gp3 volumes from snapshots
# 4. Generates PV/PVC manifests for Green cluster
# 5. Optionally applies them to Green cluster
#
# Prerequisites:
# - kubectl configured for Blue cluster
# - AWS CLI configured with appropriate permissions
# - User pods should be stopped for consistent snapshots
#
# Usage:
#   ./migrate-pvcs-ebs-snapshot.sh [--apply]
#
# Options:
#   --apply    Actually apply manifests to Green cluster (default: dry-run)
#   --force    Skip the "no active users" check
#
# Output:
#   ./migration-data/           Working directory
#   ./migration-data/pvs/       PV manifests for Green cluster
#   ./migration-data/pvcs/      PVC manifests for Green cluster

set -e

# =============================================================================
# Configuration
# =============================================================================

BLUE_NAMESPACE="daskhub"
GREEN_NAMESPACE="daskhub"
GREEN_CLUSTER_CONTEXT=""  # Set this or pass via --green-context
TARGET_AZ="us-west-2a"    # Must match Green cluster's user node AZ
STORAGE_CLASS="gp3"
GP3_IOPS="3000"
GP3_THROUGHPUT="125"

WORK_DIR="./migration-data"
APPLY_MODE=false
FORCE_MODE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --apply)
            APPLY_MODE=true
            shift
            ;;
        --force)
            FORCE_MODE=true
            shift
            ;;
        --green-context)
            GREEN_CLUSTER_CONTEXT="$2"
            shift 2
            ;;
        --target-az)
            TARGET_AZ="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# =============================================================================
# Setup
# =============================================================================

mkdir -p "$WORK_DIR/pvs" "$WORK_DIR/pvcs" "$WORK_DIR/logs"
LOG_FILE="$WORK_DIR/logs/migration-$(date +%Y%m%d-%H%M%S).log"

log() {
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a "$LOG_FILE"
}

error() {
    log "ERROR: $*"
    exit 1
}

log "=== PVC Migration: EBS Snapshot Method ==="
log "Blue namespace: $BLUE_NAMESPACE"
log "Green namespace: $GREEN_NAMESPACE"
log "Target AZ: $TARGET_AZ"
log "Apply mode: $APPLY_MODE"

# =============================================================================
# Step 0: Safety Check - Ensure no active users
# =============================================================================

log ""
log "=== Step 0: Checking for active users ==="

ACTIVE_PODS=$(kubectl get pods -n $BLUE_NAMESPACE -l component=singleuser-server \
    --field-selector=status.phase=Running -o name 2>/dev/null | wc -l)

if [ "$ACTIVE_PODS" -gt 0 ] && [ "$FORCE_MODE" = false ]; then
    log "Found $ACTIVE_PODS active user pods:"
    kubectl get pods -n $BLUE_NAMESPACE -l component=singleuser-server \
        --field-selector=status.phase=Running -o custom-columns=NAME:.metadata.name,USER:.metadata.labels.hub\\.jupyter\\.org/username
    error "Cannot migrate while users are active. Stop user pods first or use --force"
fi

log "✓ No active users (or --force specified)"

# =============================================================================
# Step 1: Collect PVC Information
# =============================================================================

log ""
log "=== Step 1: Collecting PVC information ==="

kubectl get pvc -n $BLUE_NAMESPACE -o json | jq -r '
    .items[] |
    select(.metadata.name | startswith("claim-")) |
    [.metadata.name, .spec.volumeName, .spec.resources.requests.storage, .metadata.labels["hub.jupyter.org/username"] // "unknown"] |
    @tsv
' > "$WORK_DIR/pvc-list.tsv"

PVC_COUNT=$(wc -l < "$WORK_DIR/pvc-list.tsv")
log "Found $PVC_COUNT user PVCs"

if [ "$PVC_COUNT" -eq 0 ]; then
    log "No PVCs to migrate"
    exit 0
fi

# =============================================================================
# Step 2: Get EBS Volume IDs
# =============================================================================

log ""
log "=== Step 2: Getting EBS volume IDs ==="

> "$WORK_DIR/pvc-volumes.tsv"

while IFS=$'\t' read -r pvc_name pv_name storage username; do
    log "  Processing: $pvc_name (user: $username)"

    # Try CSI driver format first, then legacy format
    vol_id=$(kubectl get pv "$pv_name" -o jsonpath='{.spec.csi.volumeHandle}' 2>/dev/null)

    if [ -z "$vol_id" ]; then
        # Legacy awsElasticBlockStore format
        vol_id=$(kubectl get pv "$pv_name" -o jsonpath='{.spec.awsElasticBlockStore.volumeID}' 2>/dev/null | sed 's|.*/||')
    fi

    if [ -z "$vol_id" ]; then
        log "  WARNING: Could not find volume ID for $pv_name"
        continue
    fi

    # Get current volume info
    vol_info=$(aws ec2 describe-volumes --volume-ids "$vol_id" --query 'Volumes[0].[VolumeType,Size,AvailabilityZone]' --output text 2>/dev/null || echo "unknown unknown unknown")

    echo -e "$pvc_name\t$pv_name\t$storage\t$username\t$vol_id\t$vol_info" >> "$WORK_DIR/pvc-volumes.tsv"
    log "    Volume: $vol_id ($vol_info)"
done < "$WORK_DIR/pvc-list.tsv"

# =============================================================================
# Step 3: Create EBS Snapshots
# =============================================================================

log ""
log "=== Step 3: Creating EBS snapshots ==="

> "$WORK_DIR/pvc-snapshots.tsv"
SNAPSHOT_IDS=""

while IFS=$'\t' read -r pvc_name pv_name storage username vol_id vol_type vol_size vol_az; do
    log "  Snapshotting: $vol_id ($pvc_name)..."

    snapshot_id=$(aws ec2 create-snapshot \
        --volume-id "$vol_id" \
        --description "CAE migration: $pvc_name (user: $username)" \
        --tag-specifications "ResourceType=snapshot,Tags=[
            {Key=Name,Value=cae-migrate-$pvc_name},
            {Key=OriginalPVC,Value=$pvc_name},
            {Key=OriginalPV,Value=$pv_name},
            {Key=Username,Value=$username},
            {Key=MigrationDate,Value=$(date +%Y-%m-%d)}
        ]" \
        --query 'SnapshotId' --output text)

    echo -e "$pvc_name\t$pv_name\t$storage\t$username\t$vol_id\t$snapshot_id" >> "$WORK_DIR/pvc-snapshots.tsv"
    SNAPSHOT_IDS="$SNAPSHOT_IDS $snapshot_id"
    log "    Created: $snapshot_id"
done < "$WORK_DIR/pvc-volumes.tsv"

# =============================================================================
# Step 4: Wait for Snapshots to Complete
# =============================================================================

log ""
log "=== Step 4: Waiting for snapshots to complete ==="

for snap_id in $SNAPSHOT_IDS; do
    log "  Waiting for $snap_id..."
    aws ec2 wait snapshot-completed --snapshot-ids "$snap_id"
    log "    ✓ Complete"
done

log "All snapshots completed"

# =============================================================================
# Step 5: Create gp3 Volumes from Snapshots
# =============================================================================

log ""
log "=== Step 5: Creating gp3 volumes ==="

> "$WORK_DIR/green-volumes.tsv"

while IFS=$'\t' read -r pvc_name pv_name storage username vol_id snapshot_id; do
    size_gb=$(echo "$storage" | sed 's/Gi//')

    log "  Creating gp3 volume from $snapshot_id..."

    new_vol_id=$(aws ec2 create-volume \
        --availability-zone "$TARGET_AZ" \
        --snapshot-id "$snapshot_id" \
        --volume-type gp3 \
        --iops "$GP3_IOPS" \
        --throughput "$GP3_THROUGHPUT" \
        --encrypted \
        --tag-specifications "ResourceType=volume,Tags=[
            {Key=Name,Value=cae-green-$pvc_name},
            {Key=OriginalPVC,Value=$pvc_name},
            {Key=Username,Value=$username},
            {Key=kubernetes.io/created-for/pvc/name,Value=$pvc_name},
            {Key=kubernetes.io/created-for/pvc/namespace,Value=$GREEN_NAMESPACE},
            {Key=MigrationDate,Value=$(date +%Y-%m-%d)}
        ]" \
        --query 'VolumeId' --output text)

    echo -e "$pvc_name\t$pv_name\t$storage\t$username\t$new_vol_id\t$snapshot_id" >> "$WORK_DIR/green-volumes.tsv"
    log "    Created: $new_vol_id"
done < "$WORK_DIR/pvc-snapshots.tsv"

# Wait for volumes to be available
log ""
log "Waiting for volumes to be available..."
cut -f5 "$WORK_DIR/green-volumes.tsv" | xargs aws ec2 wait volume-available --volume-ids
log "All volumes available"

# =============================================================================
# Step 6: Generate Kubernetes Manifests
# =============================================================================

log ""
log "=== Step 6: Generating Kubernetes manifests ==="

while IFS=$'\t' read -r pvc_name pv_name storage username new_vol_id snapshot_id; do
    log "  Generating manifests for $pvc_name (user: $username)..."

    # Sanitize username for Kubernetes naming (replace @ with -)
    safe_username=$(echo "$username" | tr '@.' '--')

    # PV manifest
    cat > "$WORK_DIR/pvs/pv-$safe_username.yaml" <<EOF
# Migrated PV for user: $username
# Original PVC: $pvc_name
# Source snapshot: $snapshot_id
# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-migrated-$safe_username
  labels:
    migrated: "true"
    migration-source: "blue-cluster"
    original-pvc: "$pvc_name"
    username: "$safe_username"
spec:
  capacity:
    storage: $storage
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: $STORAGE_CLASS
  csi:
    driver: ebs.csi.aws.com
    volumeHandle: $new_vol_id
    fsType: ext4
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: topology.kubernetes.io/zone
          operator: In
          values:
          - $TARGET_AZ
EOF

    # PVC manifest (to bind to the PV)
    cat > "$WORK_DIR/pvcs/pvc-$safe_username.yaml" <<EOF
# Migrated PVC for user: $username
# This will bind to pv-migrated-$safe_username
# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $pvc_name
  namespace: $GREEN_NAMESPACE
  labels:
    migrated: "true"
    migration-source: "blue-cluster"
    hub.jupyter.org/username: "$username"
    component: singleuser-storage
  annotations:
    hub.jupyter.org/username: "$username"
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: $storage
  storageClassName: $STORAGE_CLASS
  volumeName: pv-migrated-$safe_username
EOF

    log "    ✓ Created PV and PVC manifests"
done < "$WORK_DIR/green-volumes.tsv"

# =============================================================================
# Step 7: Apply to Green Cluster (if --apply)
# =============================================================================

log ""
log "=== Step 7: Apply manifests ==="

if [ "$APPLY_MODE" = true ]; then
    if [ -z "$GREEN_CLUSTER_CONTEXT" ]; then
        error "Green cluster context not specified. Use --green-context"
    fi

    log "Applying PVs to Green cluster..."
    kubectl --context="$GREEN_CLUSTER_CONTEXT" apply -f "$WORK_DIR/pvs/"

    log "Applying PVCs to Green cluster..."
    kubectl --context="$GREEN_CLUSTER_CONTEXT" apply -f "$WORK_DIR/pvcs/"

    log ""
    log "Verifying PVC bindings..."
    sleep 5
    kubectl --context="$GREEN_CLUSTER_CONTEXT" get pvc -n "$GREEN_NAMESPACE" -l migrated=true
else
    log "Dry-run mode. To apply manifests, run:"
    log "  kubectl apply -f $WORK_DIR/pvs/"
    log "  kubectl apply -f $WORK_DIR/pvcs/"
    log ""
    log "Or re-run with --apply --green-context <context>"
fi

# =============================================================================
# Summary
# =============================================================================

log ""
log "=== Migration Summary ==="
log "PVCs processed: $PVC_COUNT"
log "Snapshots created: $(wc -l < "$WORK_DIR/pvc-snapshots.tsv")"
log "gp3 volumes created: $(wc -l < "$WORK_DIR/green-volumes.tsv")"
log "Manifests generated: $WORK_DIR/pvs/ and $WORK_DIR/pvcs/"
log "Log file: $LOG_FILE"
log ""
log "Next steps:"
log "1. Review generated manifests in $WORK_DIR/"
log "2. Apply to Green cluster: kubectl apply -f $WORK_DIR/pvs/ -f $WORK_DIR/pvcs/"
log "3. Verify PVC bindings: kubectl get pvc -n $GREEN_NAMESPACE -l migrated=true"
log "4. Test user login on Green cluster"
log "5. After validation, optionally delete Blue cluster snapshots/volumes"

# =============================================================================
# Cleanup Script Generation
# =============================================================================

cat > "$WORK_DIR/cleanup-blue-resources.sh" <<'CLEANUP'
#!/bin/bash
# cleanup-blue-resources.sh
# Run this AFTER successful migration validation to clean up snapshots
# WARNING: This deletes data! Only run after confirming Green cluster works.

set -e

echo "=== Cleanup Blue Migration Resources ==="
echo "This will delete migration snapshots. Green volumes will be preserved."
read -p "Are you sure? (type 'yes' to confirm): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 1
fi

# Delete snapshots
for snap_id in $(aws ec2 describe-snapshots --filters "Name=tag:Name,Values=cae-migrate-*" --query 'Snapshots[].SnapshotId' --output text); do
    echo "Deleting snapshot: $snap_id"
    aws ec2 delete-snapshot --snapshot-id "$snap_id"
done

echo "Cleanup complete."
CLEANUP

chmod +x "$WORK_DIR/cleanup-blue-resources.sh"
log "Cleanup script generated: $WORK_DIR/cleanup-blue-resources.sh"
