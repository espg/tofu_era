#!/bin/bash
# Bootstrap script for Terraform backend infrastructure
# This creates the S3 bucket and DynamoDB table needed for remote state

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
ENV=${1:-dev}

# Get AWS account ID for unique bucket naming
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)

# Try to read region from terraform.tfvars first, fallback to argument or default
TFVARS_PATH="$(dirname "$0")/../environments/${ENV}/terraform.tfvars"
if [ -f "${TFVARS_PATH}" ]; then
    REGION=$(grep '^region' "${TFVARS_PATH}" | awk '{print $3}' | tr -d '"' | head -1)
    echo -e "${YELLOW}Using region from terraform.tfvars: ${REGION}${NC}"
fi

# If still not set, use provided argument or default
REGION=${REGION:-${2:-us-west-2}}

# Check if backend.tfvars already exists and read from it
BACKEND_CONFIG="$(dirname "$0")/../environments/${ENV}/backend.tfvars"
if [ -f "${BACKEND_CONFIG}" ]; then
    echo -e "${YELLOW}Reading configuration from existing backend.tfvars${NC}"
    BUCKET_NAME=$(grep '^bucket' "${BACKEND_CONFIG}" | awk '{print $3}' | tr -d '"')
    DYNAMODB_TABLE=$(grep '^dynamodb_table' "${BACKEND_CONFIG}" | awk '{print $3}' | tr -d '"')
    REGION=$(grep '^region' "${BACKEND_CONFIG}" | awk '{print $3}' | tr -d '"')
else
    # Use defaults with account ID for global uniqueness
    BUCKET_NAME="tofu-state-jupyterhub-${ENV}-${ACCOUNT_ID}"
    DYNAMODB_TABLE="tofu-state-lock-${ENV}"
fi

echo -e "${GREEN}Bootstrapping Terraform backend for environment: ${ENV}${NC}"
echo "Region: ${REGION}"
echo "Bucket: ${BUCKET_NAME}"
echo "DynamoDB Table: ${DYNAMODB_TABLE}"
echo ""

# Check if AWS CLI is configured
if ! aws sts get-caller-identity >/dev/null 2>&1; then
    echo -e "${RED}Error: AWS CLI is not configured${NC}"
    echo "Run: aws configure"
    exit 1
fi

# Create S3 bucket
echo -e "${YELLOW}Creating S3 bucket...${NC}"
if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
    echo "Bucket ${BUCKET_NAME} already exists"
else
    aws s3api create-bucket \
        --bucket "${BUCKET_NAME}" \
        --region "${REGION}" \
        $(if [ "${REGION}" != "us-east-1" ]; then echo "--create-bucket-configuration LocationConstraint=${REGION}"; fi)

    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket "${BUCKET_NAME}" \
        --versioning-configuration Status=Enabled

    # Enable encryption
    aws s3api put-bucket-encryption \
        --bucket "${BUCKET_NAME}" \
        --server-side-encryption-configuration '{
            "Rules": [{
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                }
            }]
        }'

    # Block public access
    aws s3api put-public-access-block \
        --bucket "${BUCKET_NAME}" \
        --public-access-block-configuration \
        "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

    echo -e "${GREEN}S3 bucket created successfully${NC}"
fi

# Create DynamoDB table for state locking
echo -e "${YELLOW}Creating DynamoDB table...${NC}"
if aws dynamodb describe-table --table-name "${DYNAMODB_TABLE}" --region "${REGION}" >/dev/null 2>&1; then
    echo "Table ${DYNAMODB_TABLE} already exists"
else
    aws dynamodb create-table \
        --table-name "${DYNAMODB_TABLE}" \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --region "${REGION}" \
        --tags Key=Environment,Value="${ENV}" Key=Terraform,Value=true Key=Purpose,Value=state-lock

    # Wait for table to be active
    echo "Waiting for table to be active..."
    aws dynamodb wait table-exists --table-name "${DYNAMODB_TABLE}" --region "${REGION}"

    echo -e "${GREEN}DynamoDB table created successfully${NC}"
fi

# Create backend configuration file only if it doesn't exist
if [ ! -f "${BACKEND_CONFIG}" ]; then
    echo -e "${YELLOW}Creating backend configuration...${NC}"
    cat > "${BACKEND_CONFIG}" << EOF
bucket         = "${BUCKET_NAME}"
key            = "terraform.tfstate"
region         = "${REGION}"
encrypt        = true
dynamodb_table = "${DYNAMODB_TABLE}"
EOF
    echo -e "${GREEN}Backend configuration written to ${BACKEND_CONFIG}${NC}"
else
    echo -e "${GREEN}Backend configuration already exists at ${BACKEND_CONFIG}${NC}"
fi

# Create KMS key for SOPS (optional)
echo -e "${YELLOW}Checking KMS key for SOPS...${NC}"
KMS_ALIAS="alias/sops-jupyterhub-${ENV}"

# Try to get existing key
if aws kms describe-alias --alias-name "${KMS_ALIAS}" --region "${REGION}" >/dev/null 2>&1; then
    echo "KMS alias ${KMS_ALIAS} already exists"
    KMS_KEY_ARN=$(aws kms describe-alias --alias-name "${KMS_ALIAS}" --region "${REGION}" --query 'TargetKeyId' --output text)
    KMS_KEY_ARN=$(aws kms describe-key --key-id "${KMS_KEY_ARN}" --region "${REGION}" --query 'KeyMetadata.Arn' --output text)
else
    echo "Creating new KMS key..."
    KMS_KEY_ID=$(aws kms create-key \
        --description "SOPS key for JupyterHub ${ENV}" \
        --tags TagKey=Environment,TagValue="${ENV}" TagKey=Application,TagValue=jupyterhub \
        --region "${REGION}" \
        --query 'KeyMetadata.KeyId' \
        --output text)

    aws kms create-alias \
        --alias-name "${KMS_ALIAS}" \
        --target-key-id "${KMS_KEY_ID}" \
        --region "${REGION}" 2>/dev/null || true

    KMS_KEY_ARN=$(aws kms describe-key --key-id "${KMS_KEY_ID}" --region "${REGION}" --query 'KeyMetadata.Arn' --output text)
    echo -e "${GREEN}KMS key created: ${KMS_KEY_ARN}${NC}"
fi

# Note: SOPS configuration managed at project level in .sops.yaml
echo -e "${YELLOW}Note: Add the following to your .sops.yaml:${NC}"
echo ""
echo "  - path_regex: environments/${ENV}/secrets\\.yaml\$"
echo "    kms: ${KMS_ARN}"
echo ""

# Summary
echo ""
echo -e "${GREEN}=== Bootstrap Complete ===${NC}"
echo ""
echo "Backend resources:"
echo "  S3 Bucket: ${BUCKET_NAME}"
echo "  DynamoDB Table: ${DYNAMODB_TABLE}"
echo "  KMS Key: ${KMS_ARN}"
echo "  Region: ${REGION}"
echo ""
echo "Next steps:"
echo "1. Create secrets file:"
echo "   cat > environments/${ENV}/secrets.yaml << 'EOF'"
echo "   cognito:"
echo "       client_secret: test-secret-change-me"
echo "   github:"
echo "       token: \"\""
echo "   EOF"
echo ""
echo "2. Encrypt secrets:"
echo "   sops -e -i environments/${ENV}/secrets.yaml"
echo ""
echo "3. Deploy infrastructure:"
echo "   make apply ENVIRONMENT=${ENV}"