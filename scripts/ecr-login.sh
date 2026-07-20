#!/usr/bin/env bash
set -euo pipefail

#
# ecr-login.sh — Authenticate Docker to the ECR private registry
#
# Usage:
#   ./scripts/ecr-login.sh [--region us-east-1]
#

REGION="us-east-1"

usage() {
  echo "Usage: $0 [--region <aws-region>]"
  echo ""
  echo "Examples:"
  echo "  $0                       # login in us-east-1 (default)"
  echo "  $0 --region us-east-1    # login in a specific region"
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
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

echo "Logging in to ${REGISTRY}..."
aws ecr get-login-password --region "${REGION}" | docker login --username AWS --password-stdin "${REGISTRY}"
echo "Login succeeded."
