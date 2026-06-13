#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage: $0 -b BUCKET_NAME -t TABLE_NAME [-r REGION] [-p AWS_PROFILE]

Creates an S3 bucket and a DynamoDB table (idempotent). Designed for WSL Ubuntu 24.04.

Options:
  -b BUCKET_NAME    S3 bucket name (must be globally unique)
  -t TABLE_NAME     DynamoDB table name
  -r REGION         AWS region (default: us-east-1)
  -h                Show this help
EOF
  exit 1
}

BUCKET=""
TABLE=""
REGION=""
# Fixed prefix per request. DynamoDB table keeps case; S3 bucket will be lowercased.
PREFIX="ASG-GHA-Test"


while getopts ":b:t:r:p:h" opt; do
  case ${opt} in
    b) BUCKET=${OPTARG} ;; 
    t) TABLE=${OPTARG} ;; 
    r) REGION=${OPTARG} ;; 
    h) usage ;; 
    :) echo "Option -${OPTARG} requires an argument."; usage ;; 
    *) usage ;; 
  esac
done

if [ -z "$BUCKET" ] && [ -z "$TABLE" ]; then
  # If user provided neither, we'll generate both names below.
  :
fi

# Generate a random suffix (alphanumeric lowercase) for uniqueness
RANDOM_SUFFIX=$(head /dev/urandom | tr -dc 'a-z0-9' | fold -w 8 | head -n 1)

# Build final names: prefix + random + optional user-provided base
# S3 bucket names must be lowercase and only contain a-z0-9.-
PREFIX_LOWER=$(echo "$PREFIX" | tr '[:upper:]' '[:lower:]')
if [ -n "$BUCKET" ]; then
  SANITIZED_BUCKET=$(echo "$BUCKET" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9.-]//g')
  BUCKET_FINAL="${PREFIX_LOWER}-${RANDOM_SUFFIX}-${SANITIZED_BUCKET}"
else
  BUCKET_FINAL="${PREFIX_LOWER}-${RANDOM_SUFFIX}"
fi

# DynamoDB allows mixed case; keep prefix as-is for table names
if [ -n "$TABLE" ]; then
  TABLE_FINAL="${PREFIX}-${RANDOM_SUFFIX}-${TABLE}"
else
  TABLE_FINAL="${PREFIX}-${RANDOM_SUFFIX}"
fi

AWS_CMD=(aws)
if [ -n "$REGION" ]; then
  AWS_CMD+=(--region "$REGION")
else
  REGION=us-east-1
  AWS_CMD+=(--region "$REGION")
fi

command -v aws >/dev/null 2>&1 || { echo "aws CLI not found. Install and configure it first." >&2; exit 2; }

echo "Region: $REGION"

# Create S3 bucket if it doesn't exist
echo "Checking S3 bucket '$BUCKET_FINAL'..."
if ${AWS_CMD[@]} s3api head-bucket --bucket "$BUCKET_FINAL" >/dev/null 2>&1; then
  echo "S3 bucket '$BUCKET_FINAL' already exists or is accessible. Skipping creation."
else
  echo "Creating S3 bucket '$BUCKET_FINAL'..."
  if [ "$REGION" = "us-east-1" ]; then
    ${AWS_CMD[@]} s3api create-bucket --bucket "$BUCKET_FINAL"
  else
    ${AWS_CMD[@]} s3api create-bucket --bucket "$BUCKET_FINAL" --create-bucket-configuration LocationConstraint="$REGION"
  fi
fi

# Get bucket location
BUCKET_LOCATION=$(${AWS_CMD[@]} s3api get-bucket-location --bucket "$BUCKET_FINAL" --output text 2>/dev/null || echo "$REGION")
if [ "$BUCKET_LOCATION" = "None" ]; then
  BUCKET_LOCATION=$REGION
fi

# Create DynamoDB table if missing
echo "Checking DynamoDB table '$TABLE_FINAL'..."
if ${AWS_CMD[@]} dynamodb describe-table --table-name "$TABLE_FINAL" >/dev/null 2>&1; then
  echo "DynamoDB table '$TABLE_FINAL' already exists. Skipping creation."
else
  echo "Creating DynamoDB table '$TABLE_FINAL'..."
  ${AWS_CMD[@]} dynamodb create-table \
    --table-name "$TABLE_FINAL" \
    --attribute-definitions AttributeName=Id,AttributeType=S \
    --key-schema AttributeName=Id,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST
  echo "Waiting for DynamoDB table to become ACTIVE..."
  ${AWS_CMD[@]} dynamodb wait table-exists --table-name "$TABLE_FINAL"
fi

# Gather outputs
echo "Collecting resource details..."
TABLE_DESC=$(${AWS_CMD[@]} dynamodb describe-table --table-name "$TABLE_FINAL" --output json)
TABLE_ARN=$(echo "$TABLE_DESC" | jq -r '.Table.TableArn' 2>/dev/null || echo "")
if [ -z "$TABLE_ARN" ]; then
  TABLE_ARN=$(${AWS_CMD[@]} dynamodb describe-table --table-name "$TABLE_FINAL" --query 'Table.TableArn' --output text 2>/dev/null || echo "")
fi

BUCKET_ARN="arn:aws:s3:::$BUCKET_FINAL"

# Print human-friendly summary
echo
echo "=== Summary ==="
echo "S3 Bucket: $BUCKET_FINAL"
echo "S3 Bucket ARN: $BUCKET_ARN"
echo "S3 Bucket Location: $BUCKET_LOCATION"
echo
echo "DynamoDB Table: $TABLE_FINAL"
echo "DynamoDB Table ARN: $TABLE_ARN"

# Print machine-readable JSON if jq is available
if command -v jq >/dev/null 2>&1; then
  jq -n \
    --arg bucket "$BUCKET" \
    --arg bucket_arn "$BUCKET_ARN" \
    --arg bucket_location "$BUCKET_LOCATION" \
    --arg table "$TABLE" \
    --arg table_arn "$TABLE_ARN" \
    '{s3:{name:$bucket,arn:$bucket_arn,location:$bucket_location},dynamodb:{name:$table,arn:$table_arn}}'
else
  echo
  echo '{'
  echo "  \"s3\": { \"name\": \"$BUCKET\", \"arn\": \"$BUCKET_ARN\", \"location\": \"$BUCKET_LOCATION\" },"
  echo "  \"dynamodb\": { \"name\": \"$TABLE\", \"arn\": \"$TABLE_ARN\" }"
  echo '}'
fi

exit 0
