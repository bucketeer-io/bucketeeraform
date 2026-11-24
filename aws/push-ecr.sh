#!/usr/bin/env bash
# Build images from services/ (with config/ at repo root), then push to ECR.
# Run from repo root. Requires: Docker, AWS CLI, terraform apply already run.

set -e
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

REGION="${AWS_REGION:-us-east-1}"
BUCKETEER_VERSION="${BUCKETEER_VERSION:-v2.2.0}"

if [ ! -f certs/tls.key ] || [ ! -f certs/tls.crt ] \
  || [ ! -f certs/oauth-private.pem ] || [ ! -f certs/oauth-public.pem ] \
  || [ ! -f certs/service-token ]; then
  echo "Generating example certs..."
  bash certs/generate.sh
fi

echo "Building from services/ with config/ (BUCKETEER_VERSION=${BUCKETEER_VERSION})..."
docker build --platform linux/amd64 --build-arg BUCKETEER_VERSION="${BUCKETEER_VERSION}" -f services/api/Dockerfile       -t bucketeer-api:latest       .
docker build --platform linux/amd64 --build-arg BUCKETEER_VERSION="${BUCKETEER_VERSION}" -f services/web/Dockerfile       -t bucketeer-web:latest       .
docker build --platform linux/amd64 --build-arg BUCKETEER_VERSION="${BUCKETEER_VERSION}" -f services/batch/Dockerfile     -t bucketeer-batch:latest     .
docker build --platform linux/amd64 --build-arg BUCKETEER_VERSION="${BUCKETEER_VERSION}" -f services/subscriber/Dockerfile -t bucketeer-subscriber:latest .
docker build --platform linux/amd64 -f services/nginx/Dockerfile     -t bucketeer-nginx:latest     .

# Get ECR URLs from Terraform
cd aws/modules
API_URL=$(terraform output -raw ecr_api_url 2>/dev/null || true)
WEB_URL=$(terraform output -raw ecr_web_url 2>/dev/null || true)
BATCH_URL=$(terraform output -raw ecr_batch_url 2>/dev/null || true)
SUBSCRIBER_URL=$(terraform output -raw ecr_subscriber_url 2>/dev/null || true)
NGINX_URL=$(terraform output -raw ecr_nginx_url 2>/dev/null || true)

if [[ -z "$API_URL" ]]; then
  echo "Run 'make apply-aws' first so ECR URLs exist."
  exit 1
fi

# ECR login
AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "${AWS_ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com"

tag_and_push() {
  local local_name=$1
  local ecr_url=$2
  docker tag "$local_name" "${ecr_url}:latest"
  docker push "${ecr_url}:latest"
  echo "Pushed ${ecr_url}:latest"
}

tag_and_push "bucketeer-api:latest"       "$API_URL"
tag_and_push "bucketeer-web:latest"       "$WEB_URL"
tag_and_push "bucketeer-batch:latest"     "$BATCH_URL"
tag_and_push "bucketeer-subscriber:latest" "$SUBSCRIBER_URL"
tag_and_push "bucketeer-nginx:latest"     "$NGINX_URL"

echo "Done. Config is baked in from config/. Force new deployment in ECS to pick up new images."
