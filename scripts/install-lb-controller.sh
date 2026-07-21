#!/usr/bin/env bash
set -euo pipefail

#
# install-lb-controller.sh — Install the AWS Load Balancer Controller on EKS via Helm (PETPLAT-29)
#
# Applies the controller's CRDs, adds/updates the eks-charts Helm repo, and
# installs the aws-load-balancer-controller chart with a ServiceAccount
# annotated for the IRSA role created by terraform/modules/lb-controller.
#
# Requires: aws cli, kubectl, helm >= 3, terraform (to read the IRSA role
# ARN and VPC ID from the environment's state).
#
# Usage:
#   ./scripts/install-lb-controller.sh <environment> [--chart-version <version>]
#
# Examples:
#   ./scripts/install-lb-controller.sh dev
#   ./scripts/install-lb-controller.sh prod --chart-version 1.8.1
#

REGION="${AWS_DEFAULT_REGION:-us-east-1}"
CHART_VERSION=""
CHART_REPO_URL="https://aws.github.io/eks-charts"
CRDS_URL="https://raw.githubusercontent.com/aws/eks-charts/master/stable/aws-load-balancer-controller/crds/crds.yaml"
NAMESPACE="kube-system"
SERVICE_ACCOUNT_NAME="aws-load-balancer-controller"
RELEASE_NAME="aws-load-balancer-controller"

usage() {
  echo "Usage: $0 <environment> [--chart-version <version>]"
  echo "  environment: dev | prod"
  echo ""
  echo "Examples:"
  echo "  $0 dev                          # install into the dev cluster"
  echo "  $0 prod --chart-version 1.8.1   # pin a specific chart version"
  exit 1
}

if [[ $# -lt 1 ]]; then
  usage
fi

ENV="$1"
shift

if [[ "$ENV" != "dev" && "$ENV" != "prod" ]]; then
  echo "Error: environment must be 'dev' or 'prod'"
  usage
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --chart-version)
      CHART_VERSION="$2"
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

for bin in aws kubectl helm terraform; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "Error: '$bin' is required but not found on PATH."
    exit 1
  fi
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_ENV_DIR="${SCRIPT_DIR}/../terraform/environments/${ENV}"
CLUSTER_NAME="petclinic-${ENV}"

echo "============================================"
echo "  AWS Load Balancer Controller install"
echo "  Environment: ${ENV}"
echo "  Cluster:     ${CLUSTER_NAME}"
echo "  Region:      ${REGION}"
echo "============================================"
echo ""

# --- Read the IRSA role ARN and VPC ID from Terraform outputs ---
echo "[1/5] Reading Terraform outputs from ${TF_ENV_DIR}"

ROLE_ARN=$(terraform -chdir="${TF_ENV_DIR}" output -raw lb_controller_role_arn)
VPC_ID=$(terraform -chdir="${TF_ENV_DIR}" output -raw vpc_id)

if [[ -z "${ROLE_ARN}" || -z "${VPC_ID}" ]]; then
  echo "Error: could not read lb_controller_role_arn / vpc_id from Terraform outputs."
  echo "       Run 'terraform apply' in ${TF_ENV_DIR} first."
  exit 1
fi

echo "  -> Role ARN: ${ROLE_ARN}"
echo "  -> VPC ID:   ${VPC_ID}"
echo ""

# --- Point kubectl at the target cluster ---
echo "[2/5] Updating kubeconfig for ${CLUSTER_NAME}"
aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${REGION}" >/dev/null
echo ""

# --- CRDs ---
echo "[3/5] Applying AWS Load Balancer Controller CRDs"
kubectl apply -f "${CRDS_URL}"
echo ""

# --- Helm repo ---
echo "[4/5] Adding/updating the eks-charts Helm repo"
helm repo add eks "${CHART_REPO_URL}" >/dev/null 2>&1 || true
helm repo update eks
echo ""

# --- Helm install/upgrade ---
echo "[5/5] Installing ${RELEASE_NAME} via Helm (namespace: ${NAMESPACE})"

HELM_ARGS=(
  upgrade --install "${RELEASE_NAME}" eks/aws-load-balancer-controller
  --namespace "${NAMESPACE}"
  --set "clusterName=${CLUSTER_NAME}"
  --set "region=${REGION}"
  --set "vpcId=${VPC_ID}"
  --set "serviceAccount.create=true"
  --set "serviceAccount.name=${SERVICE_ACCOUNT_NAME}"
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=${ROLE_ARN}"
)

if [[ -n "${CHART_VERSION}" ]]; then
  HELM_ARGS+=(--version "${CHART_VERSION}")
fi

helm "${HELM_ARGS[@]}"

echo ""
echo "============================================"
echo "  Install complete."
echo ""
echo "  Verify:"
echo "    kubectl get deployment -n ${NAMESPACE} ${RELEASE_NAME}"
echo "    kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=aws-load-balancer-controller"
echo "    kubectl get ingressclass"
echo ""
echo "  Then apply the Ingress to create the ALB:"
echo "    kubectl apply -f k8s/base/ingress/"
echo "============================================"
