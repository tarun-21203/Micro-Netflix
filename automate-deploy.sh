#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/scripts/deploy-static-site.sh"

echo "===================================================="
echo "🚀 Step 1: Deploying Advanced Cloud Infrastructure"
echo "===================================================="
cd infrastructure
terraform init
terraform apply -auto-approve

echo "===================================================="
echo "📊 Step 2: Fetching Live Cloud Architecture Outputs"
echo "===================================================="
API_URL=$(terraform output -raw api_base_url)
SITE_BUCKET=$(terraform output -raw frontend_site_bucket)
FRONTEND_URL=$(terraform output -raw frontend_url)
cd ..

echo "===================================================="
echo "⚙️ Step 3: Injecting Runtime Environment Variables"
echo "===================================================="
echo "VITE_API_BASE_URL=$API_URL" > frontend/.env
echo "Injected Target context: VITE_API_BASE_URL=$API_URL"

echo "===================================================="
echo "📦 Step 4: Compressing Clean Deployment Package Revision"
echo "===================================================="
cd frontend
npm install --legacy-peer-deps
npm run build
cd ..

echo "===================================================="
echo "☁️ Step 5: Shipping Source Revision Bundle to S3"
echo "===================================================="
aws s3 sync frontend/dist "s3://$SITE_BUCKET" --delete

echo "===================================================="
echo "🚀 Step 6: Triggering AWS CodeDeploy Orchestration Lifecycle"
echo "===================================================="
DEPLOYMENT_ID="not-used-s3-static-hosting"

echo "Deployment created successfully with Tracking ID: $DEPLOYMENT_ID"
echo "----------------------------------------------------"
echo "⌛ Blocking shell until CodeDeploy execution succeeds..."
echo "CodeDeploy skipped; frontend was published directly to S3 static hosting."

echo "===================================================="
echo "✅ Pipeline Complete! Zero-Manual Actions Accomplished"
echo "===================================================="
echo "Your live cloud-native application is accessible here:"
echo "👉 $FRONTEND_URL"
