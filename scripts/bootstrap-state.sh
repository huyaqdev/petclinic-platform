#!/usr/bin/env bash
set -euo pipefail

#
# bootstrap-state.sh — One-time provisioning of the Terraform remote state backend
#
# Creates the S3 bucket (versioned, encrypted, public access blocked) and the
# DynamoDB lock table used by every environment's backend.tf. Safe to re-run —
# skips any resource that already exists.
#
# Usage:
#   ./scripts/bootstrap-state.sh [--region us-east-1]
#

REGION="us-east-1"

usage() {
  echo "Usage: $0 [--region <aws-region>]"
  echo ""
  echo "Examples:"
  echo "  $0                       # bootstrap in us-east-1 (default)"
  echo "  $0 --region us-east-1    # bootstrap in a specific region"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --region)
      REGION="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Error: unknown argument '$1'"
      usage
      ;;
  esac
done

ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
BUCKET_NAME="petclinic-terraform-state-${ACCOUNT_ID}"
TABLE_NAME="petclinic-terraform-locks"

echo "============================================"
echo "  Terraform State Bootstrap"
echo "  Region:  ${REGION}"
echo "  Account: ${ACCOUNT_ID}"
echo "============================================"
echo ""

# --- S3 bucket ---
echo "--- S3 bucket: ${BUCKET_NAME} ---"

if aws s3api head-bucket --bucket "${BUCKET_NAME}" --region "${REGION}" 2>/dev/null; then
  echo "  Already exists — skipping creation."
else
  echo "  Creating bucket..."
  if [[ "${REGION}" == "us-east-1" ]]; then
    aws s3api create-bucket \
      --bucket "${BUCKET_NAME}" \
      --region "${REGION}"
  else
    aws s3api create-bucket \
      --bucket "${BUCKET_NAME}" \
      --region "${REGION}" \
      --create-bucket-configuration LocationConstraint="${REGION}"
  fi
fi

echo "  Enabling versioning..."
aws s3api put-bucket-versioning \
  --bucket "${BUCKET_NAME}" \
  --versioning-configuration Status=Enabled

echo "  Enabling default encryption (AES256)..."
aws s3api put-bucket-encryption \
  --bucket "${BUCKET_NAME}" \
  --server-side-encryption-configuration '{
    "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
  }'

echo "  Blocking all public access..."
aws s3api put-public-access-block \
  --bucket "${BUCKET_NAME}" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

echo "  Tagging bucket..."
aws s3api put-bucket-tagging \
  --bucket "${BUCKET_NAME}" \
  --tagging 'TagSet=[{Key=Project,Value=petclinic},{Key=ManagedBy,Value=terraform-bootstrap}]'

echo ""

# --- DynamoDB lock table ---
echo "--- DynamoDB table: ${TABLE_NAME} ---"

EXISTING_STATUS=$(aws dynamodb describe-table \
  --table-name "${TABLE_NAME}" \
  --region "${REGION}" \
  --query 'Table.TableStatus' \
  --output text 2>/dev/null || echo "NOT FOUND")

if [[ "${EXISTING_STATUS}" != "NOT FOUND" ]]; then
  echo "  Already exists (status: ${EXISTING_STATUS}) — skipping creation."
else
  echo "  Creating table..."
  aws dynamodb create-table \
    --table-name "${TABLE_NAME}" \
    --region "${REGION}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --tags Key=Project,Value=petclinic Key=ManagedBy,Value=terraform-bootstrap

  echo "  Waiting for table to become active..."
  aws dynamodb wait table-exists --table-name "${TABLE_NAME}" --region "${REGION}"
fi

echo ""
echo "============================================"
echo "  Bootstrap complete."
echo "  Bucket: ${BUCKET_NAME}"
echo "  Table:  ${TABLE_NAME}"
echo ""
echo "  Use these values in each environment's backend.tf:"
echo "    bucket         = \"${BUCKET_NAME}\""
echo "    dynamodb_table = \"${TABLE_NAME}\""
echo "    region         = \"${REGION}\""
echo "============================================"
