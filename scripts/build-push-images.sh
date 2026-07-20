#!/usr/bin/env bash
set -euo pipefail

#
# build-push-images.sh — Build all 8 Petclinic service images for linux/arm64
# and push them to ECR (PETPLAT-85, initial manual build; CI/E-10 handles
# subsequent builds on every commit).
#
# Builds JARs with Maven (in a maven:3.9-eclipse-temurin-17 container — no
# local JDK/Maven install required, only Docker), then builds & pushes images
# with `docker buildx`. Deliberately does NOT use the app repo's `buildDocker`
# Maven profile: that profile shells out to plain `docker build --platform
# ...`, which cannot reliably cross-compile to linux/arm64 on an x86 host.
# `docker buildx build --push` builds for the target platform and pushes
# straight to the registry without needing to load a foreign-arch image into
# the local daemon.
#
# Prerequisites:
#   - Docker with buildx, and QEMU registered for cross-platform emulation
#     (Docker Desktop does this automatically; on plain Linux run once:
#     docker run --privileged --rm tonistiigi/binfmt --install arm64)
#   - AWS credentials with ECR push access to the target account/region
#
# Usage:
#   ./scripts/build-push-images.sh --tag <tag> [--env dev|prod] [--region us-east-1] [--app-repo <path>] [--skip-build]
#
# Examples:
#   ./scripts/build-push-images.sh --tag v1.0.0
#   ./scripts/build-push-images.sh --tag v1.0.0 --env prod
#   ./scripts/build-push-images.sh --tag a1b2c3d --skip-build   # re-push jars already built under target/
#

ENV="dev"
REGION="us-east-1"
APP_REPO="../spring-petclinic-microservices"
TAG=""
SKIP_BUILD=false

SERVICES=(config-server discovery-server api-gateway customers-service visits-service vets-service genai-service admin-server)

# Runtime ports per docs/technical-spec.md's Application Services table.
# Deliberately NOT read from each service's pom.xml docker.image.exposed.port
# property — api-gateway, visits-service, vets-service, and genai-service all
# carry an incorrect copy-pasted value (8081) there.
port_for_service() {
  case "$1" in
    config-server) echo 8888 ;;
    discovery-server) echo 8761 ;;
    api-gateway) echo 8080 ;;
    customers-service) echo 8081 ;;
    visits-service) echo 8082 ;;
    vets-service) echo 8083 ;;
    genai-service) echo 8084 ;;
    admin-server) echo 9090 ;;
    *)
      echo "Error: unknown service '$1'" >&2
      exit 1
      ;;
  esac
}

usage() {
  echo "Usage: $0 --tag <tag> [--env dev|prod] [--region us-east-1] [--app-repo <path>] [--skip-build]"
  echo ""
  echo "Examples:"
  echo "  $0 --tag v1.0.0"
  echo "  $0 --tag v1.0.0 --env prod"
  echo "  $0 --tag a1b2c3d --skip-build"
  echo "  $0 --tag v1.0.0 --app-repo /path/to/spring-petclinic-microservices"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      TAG="$2"
      shift 2
      ;;
    --env)
      ENV="$2"
      shift 2
      ;;
    --region)
      REGION="$2"
      shift 2
      ;;
    --app-repo)
      APP_REPO="$2"
      shift 2
      ;;
    --skip-build)
      SKIP_BUILD=true
      shift
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

if [[ -z "${TAG}" ]]; then
  echo "Error: --tag is required (e.g. --tag v1.0.0 or a commit SHA). Never use 'latest'."
  usage
fi
if [[ "${ENV}" != "dev" && "${ENV}" != "prod" ]]; then
  echo "Error: --env must be 'dev' or 'prod'"
  exit 1
fi
if [[ ! -d "${APP_REPO}" ]]; then
  echo "Error: app repo not found at '${APP_REPO}' (pass --app-repo /path/to/spring-petclinic-microservices)"
  exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "============================================"
echo "  Build & Push Petclinic Images"
echo "  Environment: petclinic-${ENV}"
echo "  Registry:    ${REGISTRY}"
echo "  Tag:         ${TAG}"
echo "  App repo:    ${APP_REPO}"
echo "============================================"
echo ""

echo "--- ECR login ---"
"${SCRIPT_DIR}/ecr-login.sh" --region "${REGION}"
echo ""

if [[ "${SKIP_BUILD}" == "false" ]]; then
  echo "--- Building JARs with Maven (containerized — no local JDK/Maven required) ---"
  APP_REPO_ABS="$(cd "${APP_REPO}" && pwd)"
  MSYS_NO_PATHCONV=1 docker run --rm \
    -v "${APP_REPO_ABS}:/workspace" \
    -v maven-repo-cache:/root/.m2 \
    -w /workspace \
    maven:3.9-eclipse-temurin-17 \
    mvn -B clean package -DskipTests
  echo ""
else
  echo "--- Skipping Maven build (--skip-build), using existing target/ jars ---"
  echo ""
fi

echo "--- Ensuring a buildx builder that supports linux/arm64 ---"
if ! docker buildx inspect petclinic-builder >/dev/null 2>&1; then
  docker buildx create --name petclinic-builder --driver docker-container --bootstrap
fi
docker buildx use petclinic-builder
echo ""

PUSHED_URIS=()

for service in "${SERVICES[@]}"; do
  MODULE_DIR="${APP_REPO}/spring-petclinic-${service}"
  JAR_PATH=$(find "${MODULE_DIR}/target" -maxdepth 1 -name "spring-petclinic-${service}-*.jar" ! -name "*-sources.jar" ! -name "*-javadoc.jar" | head -1)

  if [[ -z "${JAR_PATH}" ]]; then
    echo "Error: no built jar found for ${service} under ${MODULE_DIR}/target/ (did the Maven build succeed?)" >&2
    exit 1
  fi

  ARTIFACT_NAME=$(basename "${JAR_PATH}" .jar)
  PORT=$(port_for_service "${service}")
  IMAGE_URI="${REGISTRY}/petclinic-${ENV}/${service}:${TAG}"

  echo "--- Building & pushing ${service} (port ${PORT}, artifact ${ARTIFACT_NAME}) ---"
  docker buildx build \
    --platform linux/arm64 \
    -f "${APP_REPO}/docker/Dockerfile" \
    --build-arg ARTIFACT_NAME="${ARTIFACT_NAME}" \
    --build-arg EXPOSED_PORT="${PORT}" \
    -t "${IMAGE_URI}" \
    --push \
    "${MODULE_DIR}/target"

  PUSHED_URIS+=("${IMAGE_URI}")
  echo ""
done

echo "============================================"
echo "  Done. Pushed ${#PUSHED_URIS[@]} images:"
for uri in "${PUSHED_URIS[@]}"; do
  echo "    ${uri}"
done
echo "============================================"
