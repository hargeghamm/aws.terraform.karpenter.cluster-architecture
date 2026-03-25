#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# bootstrap-backend.sh
#
# One-time script to create the S3 bucket and DynamoDB table used for
# Terraform remote state and state locking.
#
# Usage:
#   chmod +x scripts/bootstrap-backend.sh
#   ./scripts/bootstrap-backend.sh                        # uses defaults
#   REGION=us-east-1 BUCKET_SUFFIX=myteam ./scripts/bootstrap-backend.sh
#
# Safe to re-run — existing resources are detected and skipped.
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ──────────── Configuration (override via env vars) ────────────
REGION="${REGION:-eu-central-1}"
BUCKET_NAME="${BUCKET_NAME:-tf-state-startup-eks-poc}"
DYNAMODB_TABLE="${DYNAMODB_TABLE:-terraform-state-lock}"

echo "==> Bootstrap Terraform backend"
echo "    Region         : ${REGION}"
echo "    S3 bucket      : ${BUCKET_NAME}"
echo "    DynamoDB table : ${DYNAMODB_TABLE}"
echo ""

# ───────────────── S3 bucket ─────────────────
if aws s3api head-bucket --bucket "${BUCKET_NAME}" --region "${REGION}" 2>/dev/null; then
  echo "[SKIP] S3 bucket '${BUCKET_NAME}' already exists."
else
  echo "[CREATE] S3 bucket '${BUCKET_NAME}' ..."

  if [ "${REGION}" = "us-east-1" ]; then
    # us-east-1 does not accept a LocationConstraint
    aws s3api create-bucket \
      --bucket "${BUCKET_NAME}" \
      --region "${REGION}"
  else
    aws s3api create-bucket \
      --bucket "${BUCKET_NAME}" \
      --region "${REGION}" \
      --create-bucket-configuration LocationConstraint="${REGION}"
  fi

  # Block all public access
  aws s3api put-public-access-block \
    --bucket "${BUCKET_NAME}" \
    --public-access-block-configuration \
      "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

  # Enable versioning so previous state files can be recovered
  aws s3api put-bucket-versioning \
    --bucket "${BUCKET_NAME}" \
    --versioning-configuration Status=Enabled

  # Enable server-side encryption (AES-256)
  aws s3api put-bucket-encryption \
    --bucket "${BUCKET_NAME}" \
    --server-side-encryption-configuration '{
      "Rules": [{
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "AES256"
        },
        "BucketKeyEnabled": true
      }]
    }'

  echo "[OK] S3 bucket created and hardened."
fi

# ──────────────── DynamoDB table ────────────────
if aws dynamodb describe-table \
     --table-name "${DYNAMODB_TABLE}" \
     --region "${REGION}" \
     --query 'Table.TableName' \
     --output text 2>/dev/null | grep -q "${DYNAMODB_TABLE}"; then
  echo "[SKIP] DynamoDB table '${DYNAMODB_TABLE}' already exists."
else
  echo "[CREATE] DynamoDB table '${DYNAMODB_TABLE}' ..."

  aws dynamodb create-table \
    --table-name "${DYNAMODB_TABLE}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "${REGION}"

  # Wait until the table is active before returning
  aws dynamodb wait table-exists \
    --table-name "${DYNAMODB_TABLE}" \
    --region "${REGION}"

  echo "[OK] DynamoDB table created."
fi

echo ""
echo "==> Done. Update backend.tf with:"
echo "      bucket         = \"${BUCKET_NAME}\""
echo "      region         = \"${REGION}\""
echo "      dynamodb_table = \"${DYNAMODB_TABLE}\""
echo ""
echo "    Then run: terraform init"
