#!/bin/bash
# migrate-pvcs-velero.sh
#
# Option 3: Velero-based PVC Migration (gp2 → gp3)
#
# This script:
# 1. Installs Velero on Blue cluster (if not present)
# 2. Creates a backup of all user PVCs with volume snapshots
# 3. Exports backup to S3
# 4. Installs Velero on Green cluster
# 5. Restores PVCs to Green cluster (new gp3 volumes created)
#
# Prerequisites:
# - kubectl configured for both clusters
# - AWS CLI configured with appropriate permissions
# - S3 bucket for Velero backups
# - IAM role/user with Velero permissions
#
# Key Advantage over EBS Snapshot method:
# - Velero handles PV/PVC binding automatically
# - Can restore subsets of resources
# - Built-in backup scheduling
# - Handles Kubernetes metadata correctly
#
# Usage:
#   ./migrate-pvcs-velero.sh setup-blue     # Install Velero on Blue
#   ./migrate-pvcs-velero.sh backup         # Create backup on Blue
#   ./migrate-pvcs-velero.sh setup-green    # Install Velero on Green
#   ./migrate-pvcs-velero.sh restore        # Restore to Green
#   ./migrate-pvcs-velero.sh status         # Check backup/restore status
#   ./migrate-pvcs-velero.sh all            # Run full migration

set -e

# =============================================================================
# Configuration
# =============================================================================

VELERO_VERSION="v1.13.0"
AWS_REGION="us-west-2"
VELERO_BUCKET="cae-velero-backups"  # S3 bucket for Velero
VELERO_PREFIX="cae-migration"

BLUE_NAMESPACE="daskhub"
GREEN_NAMESPACE="daskhub"

BLUE_CONTEXT="${BLUE_CONTEXT:-}"    # Set via env or --blue-context
GREEN_CONTEXT="${GREEN_CONTEXT:-}"  # Set via env or --green-context

BACKUP_NAME="cae-user-homes-$(date +%Y%m%d-%H%M%S)"

WORK_DIR="./velero-migration"
mkdir -p "$WORK_DIR/logs"
LOG_FILE="$WORK_DIR/logs/velero-$(date +%Y%m%d-%H%M%S).log"

# =============================================================================
# Helpers
# =============================================================================

log() {
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a "$LOG_FILE"
}

error() {
    log "ERROR: $*"
    exit 1
}

check_velero_installed() {
    if ! command -v velero &> /dev/null; then
        error "Velero CLI not found. Install from https://velero.io/docs/v1.13/basic-install/#install-the-cli"
    fi
}

switch_context() {
    local context="$1"
    if [ -n "$context" ]; then
        kubectl config use-context "$context"
        log "Switched to context: $context"
    fi
}

# =============================================================================
# IAM Policy for Velero
# =============================================================================

generate_iam_policy() {
    cat > "$WORK_DIR/velero-iam-policy.json" <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeVolumes",
                "ec2:DescribeSnapshots",
                "ec2:CreateTags",
                "ec2:CreateVolume",
                "ec2:CreateSnapshot",
                "ec2:DeleteSnapshot"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:DeleteObject",
                "s3:PutObject",
                "s3:AbortMultipartUpload",
                "s3:ListMultipartUploadParts"
            ],
            "Resource": "arn:aws:s3:::${VELERO_BUCKET}/*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket"
            ],
            "Resource": "arn:aws:s3:::${VELERO_BUCKET}"
        }
    ]
}
EOF
    log "Generated IAM policy: $WORK_DIR/velero-iam-policy.json"
}

# =============================================================================
# Setup Functions
# =============================================================================

create_s3_bucket() {
    log "=== Creating S3 Bucket for Velero ==="

    if aws s3api head-bucket --bucket "$VELERO_BUCKET" 2>/dev/null; then
        log "Bucket $VELERO_BUCKET already exists"
    else
        aws s3api create-bucket \
            --bucket "$VELERO_BUCKET" \
            --region "$AWS_REGION" \
            --create-bucket-configuration LocationConstraint="$AWS_REGION"

        # Enable versioning for safety
        aws s3api put-bucket-versioning \
            --bucket "$VELERO_BUCKET" \
            --versioning-configuration Status=Enabled

        log "Created bucket: $VELERO_BUCKET"
    fi
}

create_credentials_file() {
    # Create credentials file from environment or prompt
    if [ -f "$WORK_DIR/credentials-velero" ]; then
        log "Using existing credentials file"
        return
    fi

    if [ -n "$AWS_ACCESS_KEY_ID" ] && [ -n "$AWS_SECRET_ACCESS_KEY" ]; then
        cat > "$WORK_DIR/credentials-velero" <<EOF
[default]
aws_access_key_id=$AWS_ACCESS_KEY_ID
aws_secret_access_key=$AWS_SECRET_ACCESS_KEY
EOF
        log "Created credentials file from environment"
    else
        error "Set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY, or create $WORK_DIR/credentials-velero"
    fi
}

install_velero() {
    local cluster_name="$1"

    log "=== Installing Velero on $cluster_name ==="

    check_velero_installed
    create_credentials_file

    # Check if already installed
    if kubectl get namespace velero &>/dev/null; then
        log "Velero namespace exists, checking installation..."
        if kubectl get deployment velero -n velero &>/dev/null; then
            log "Velero already installed"
            return
        fi
    fi

    velero install \
        --provider aws \
        --plugins velero/velero-plugin-for-aws:v1.9.0 \
        --bucket "$VELERO_BUCKET" \
        --prefix "$VELERO_PREFIX" \
        --backup-location-config region="$AWS_REGION" \
        --snapshot-location-config region="$AWS_REGION" \
        --secret-file "$WORK_DIR/credentials-velero" \
        --use-volume-snapshots=true \
        --default-volumes-to-fs-backup=false

    log "Waiting for Velero deployment..."
    kubectl wait --for=condition=available deployment/velero -n velero --timeout=300s

    log "Velero installed successfully"
}

# =============================================================================
# Backup Functions
# =============================================================================

create_backup() {
    log "=== Creating Velero Backup ==="

    # Check for active users
    ACTIVE_PODS=$(kubectl get pods -n $BLUE_NAMESPACE -l component=singleuser-server \
        --field-selector=status.phase=Running -o name 2>/dev/null | wc -l)

    if [ "$ACTIVE_PODS" -gt 0 ]; then
        log "WARNING: $ACTIVE_PODS active user pods found"
        log "For consistent snapshots, consider stopping user pods first"
        read -p "Continue anyway? (y/n): " confirm
        [ "$confirm" != "y" ] && exit 1
    fi

    # Create backup with volume snapshots
    log "Creating backup: $BACKUP_NAME"

    velero backup create "$BACKUP_NAME" \
        --include-namespaces "$BLUE_NAMESPACE" \
        --include-resources persistentvolumeclaims,persistentvolumes \
        --selector 'component=singleuser-storage' \
        --snapshot-volumes=true \
        --snapshot-move-data=false \
        --wait

    # If selector doesn't work, try label-less backup
    if [ "$(velero backup describe "$BACKUP_NAME" --details -o json | jq '.status.phase')" != '"Completed"' ]; then
        log "Label selector backup had issues, trying name-based approach..."

        # Get list of claim-* PVCs
        PVCS=$(kubectl get pvc -n "$BLUE_NAMESPACE" -o name | grep "claim-" | tr '\n' ',' | sed 's/,$//')

        BACKUP_NAME="${BACKUP_NAME}-retry"
        velero backup create "$BACKUP_NAME" \
            --include-namespaces "$BLUE_NAMESPACE" \
            --include-resources persistentvolumeclaims,persistentvolumes \
            --snapshot-volumes=true \
            --wait
    fi

    # Save backup name for restore
    echo "$BACKUP_NAME" > "$WORK_DIR/latest-backup-name.txt"
    log "Backup created: $BACKUP_NAME"
}

check_backup_status() {
    log "=== Backup Status ==="

    if [ -f "$WORK_DIR/latest-backup-name.txt" ]; then
        BACKUP_NAME=$(cat "$WORK_DIR/latest-backup-name.txt")
    fi

    velero backup describe "$BACKUP_NAME" --details

    log ""
    log "Volume snapshots:"
    velero backup describe "$BACKUP_NAME" -o json | jq '.status.volumeSnapshotsAttempted, .status.volumeSnapshotsCompleted'
}

# =============================================================================
# Restore Functions
# =============================================================================

restore_backup() {
    log "=== Restoring Velero Backup to Green Cluster ==="

    if [ -f "$WORK_DIR/latest-backup-name.txt" ]; then
        BACKUP_NAME=$(cat "$WORK_DIR/latest-backup-name.txt")
    fi

    log "Restoring from backup: $BACKUP_NAME"

    RESTORE_NAME="cae-restore-$(date +%Y%m%d-%H%M%S)"

    # Restore PVCs - Velero will create new volumes from snapshots
    # The new volumes will use the default storage class (gp3)
    velero restore create "$RESTORE_NAME" \
        --from-backup "$BACKUP_NAME" \
        --include-resources persistentvolumeclaims,persistentvolumes \
        --namespace-mappings "${BLUE_NAMESPACE}:${GREEN_NAMESPACE}" \
        --wait

    echo "$RESTORE_NAME" > "$WORK_DIR/latest-restore-name.txt"
    log "Restore created: $RESTORE_NAME"
}

check_restore_status() {
    log "=== Restore Status ==="

    if [ -f "$WORK_DIR/latest-restore-name.txt" ]; then
        RESTORE_NAME=$(cat "$WORK_DIR/latest-restore-name.txt")
    fi

    velero restore describe "$RESTORE_NAME" --details

    log ""
    log "Restored PVCs:"
    kubectl get pvc -n "$GREEN_NAMESPACE" -o wide
}

# =============================================================================
# Verification
# =============================================================================

verify_migration() {
    log "=== Verifying Migration ==="

    log "PVCs in Green cluster:"
    kubectl get pvc -n "$GREEN_NAMESPACE" -o custom-columns=\
NAME:.metadata.name,\
STATUS:.status.phase,\
VOLUME:.spec.volumeName,\
STORAGE:.spec.resources.requests.storage

    log ""
    log "PVs in Green cluster:"
    kubectl get pv -o custom-columns=\
NAME:.metadata.name,\
CAPACITY:.spec.capacity.storage,\
STATUS:.status.phase,\
CLAIM:.spec.claimRef.name,\
STORAGECLASS:.spec.storageClassName

    log ""
    log "Checking volume types..."
    for pv in $(kubectl get pv -o name); do
        vol_id=$(kubectl get "$pv" -o jsonpath='{.spec.csi.volumeHandle}' 2>/dev/null)
        if [ -n "$vol_id" ]; then
            vol_type=$(aws ec2 describe-volumes --volume-ids "$vol_id" --query 'Volumes[0].VolumeType' --output text 2>/dev/null || echo "unknown")
            log "  $pv: $vol_type"
        fi
    done
}

# =============================================================================
# Full Migration
# =============================================================================

run_full_migration() {
    log "=== Running Full Velero Migration ==="

    # Step 1: Setup
    create_s3_bucket
    generate_iam_policy

    # Step 2: Install on Blue
    log ""
    log ">>> Step 2: Setting up Blue cluster <<<"
    switch_context "$BLUE_CONTEXT"
    install_velero "Blue"

    # Step 3: Create backup
    log ""
    log ">>> Step 3: Creating backup <<<"
    create_backup
    check_backup_status

    # Step 4: Install on Green
    log ""
    log ">>> Step 4: Setting up Green cluster <<<"
    switch_context "$GREEN_CONTEXT"
    install_velero "Green"

    # Step 5: Restore
    log ""
    log ">>> Step 5: Restoring to Green <<<"
    restore_backup
    check_restore_status

    # Step 6: Verify
    log ""
    log ">>> Step 6: Verification <<<"
    verify_migration

    log ""
    log "=== Migration Complete ==="
    log "Next steps:"
    log "1. Test user login on Green cluster"
    log "2. Verify user data is accessible"
    log "3. Perform DNS cutover"
    log "4. Delete Blue cluster resources after validation"
}

# =============================================================================
# Main
# =============================================================================

print_usage() {
    cat <<EOF
Usage: $0 <command> [options]

Commands:
  setup-blue      Install Velero on Blue cluster
  backup          Create backup of user PVCs on Blue
  setup-green     Install Velero on Green cluster
  restore         Restore PVCs to Green cluster
  status          Check backup/restore status
  verify          Verify migration results
  all             Run full migration (all steps)

Options:
  --blue-context   kubectl context for Blue cluster
  --green-context  kubectl context for Green cluster
  --bucket         S3 bucket for Velero (default: $VELERO_BUCKET)
  --backup-name    Specific backup name to use

Environment Variables:
  BLUE_CONTEXT     kubectl context for Blue cluster
  GREEN_CONTEXT    kubectl context for Green cluster
  AWS_ACCESS_KEY_ID
  AWS_SECRET_ACCESS_KEY

Examples:
  # Full migration
  export BLUE_CONTEXT=arn:aws:eks:us-west-2:123:cluster/blue
  export GREEN_CONTEXT=arn:aws:eks:us-west-2:123:cluster/green
  $0 all

  # Step by step
  $0 setup-blue --blue-context my-blue-cluster
  $0 backup
  $0 setup-green --green-context my-green-cluster
  $0 restore
  $0 verify
EOF
}

# Parse command
COMMAND="${1:-}"
shift || true

# Parse options
while [[ $# -gt 0 ]]; do
    case $1 in
        --blue-context)
            BLUE_CONTEXT="$2"
            shift 2
            ;;
        --green-context)
            GREEN_CONTEXT="$2"
            shift 2
            ;;
        --bucket)
            VELERO_BUCKET="$2"
            shift 2
            ;;
        --backup-name)
            BACKUP_NAME="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
done

case "$COMMAND" in
    setup-blue)
        switch_context "$BLUE_CONTEXT"
        create_s3_bucket
        install_velero "Blue"
        ;;
    backup)
        switch_context "$BLUE_CONTEXT"
        create_backup
        check_backup_status
        ;;
    setup-green)
        switch_context "$GREEN_CONTEXT"
        install_velero "Green"
        ;;
    restore)
        switch_context "$GREEN_CONTEXT"
        restore_backup
        check_restore_status
        ;;
    status)
        check_backup_status 2>/dev/null || true
        check_restore_status 2>/dev/null || true
        ;;
    verify)
        verify_migration
        ;;
    all)
        run_full_migration
        ;;
    *)
        print_usage
        exit 1
        ;;
esac
