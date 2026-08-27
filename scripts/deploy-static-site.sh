#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFRA_DIR="$ROOT_DIR/infrastructure"
FRONTEND_DIR="$ROOT_DIR/frontend"

echo "===================================================="
echo "Step 1: Deploying AWS infrastructure"
echo "===================================================="
cd "$INFRA_DIR"
ENABLE_REDIS_CACHE="${ENABLE_REDIS_CACHE:-true}"
echo "Redis cache enabled: $ENABLE_REDIS_CACHE"
terraform init
terraform apply -auto-approve -var "enable_redis_cache=$ENABLE_REDIS_CACHE"

echo "===================================================="
echo "Step 2: Reading Terraform outputs"
echo "===================================================="
API_URL="$(terraform output -raw api_base_url)"
SITE_BUCKET="$(terraform output -raw frontend_site_bucket)"
FRONTEND_URL="$(terraform output -raw frontend_url)"
COGNITO_CLIENT_ID="$(terraform output -raw cognito_user_pool_client_id)"
COGNITO_DOMAIN="$(terraform output -raw cognito_hosted_ui_domain)"

echo "===================================================="
echo "Step 3: Writing frontend environment"
echo "===================================================="
{
  printf 'VITE_API_BASE_URL=%s\n' "$API_URL"
  printf 'VITE_COGNITO_CLIENT_ID=%s\n' "$COGNITO_CLIENT_ID"
  printf 'VITE_COGNITO_DOMAIN=%s\n' "$COGNITO_DOMAIN"
  printf 'VITE_APP_URL=%s\n' "$FRONTEND_URL"
} > "$FRONTEND_DIR/.env"
cp "$FRONTEND_DIR/.env" "$FRONTEND_DIR/.env.production"
echo "API endpoint: $API_URL"
echo "Frontend endpoint: $FRONTEND_URL"

echo "===================================================="
echo "Step 4: Building React frontend"
echo "===================================================="
cd "$FRONTEND_DIR"
npm install --legacy-peer-deps
npm run build

echo "===================================================="
echo "Step 5: Publishing frontend to S3 static website"
echo "===================================================="
DIST_DIR="$FRONTEND_DIR/dist"

if [ ! -d "$DIST_DIR" ]; then
  echo "ERROR: frontend build output was not found at: $DIST_DIR"
  exit 1
fi

if command -v cygpath >/dev/null 2>&1; then
  DIST_DIR_FOR_AWS="$(cygpath -w "$DIST_DIR")"
else
  DIST_DIR_FOR_AWS="$DIST_DIR"
fi

aws s3 sync "$DIST_DIR_FOR_AWS" "s3://$SITE_BUCKET" --delete

echo "===================================================="
echo "Deployment complete"
echo "===================================================="
echo "Frontend URL:"
echo "$FRONTEND_URL"
echo
echo "API URL:"
echo "$API_URL"
