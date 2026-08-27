#!/bin/bash
set -e

# Establish path environment variables for root execution context
export HOME=/home/ubuntu
export PATH=$PATH:/usr/bin:/usr/local/bin

echo "===================================================="
echo "📦 Phase 1: Installing Frontend Dependencies"
echo "===================================================="
cd /home/ubuntu/app-workspace
npm install --legacy-peer-deps
chmod -R +x node_modules/.bin

echo "===================================================="
echo "🛠️ Phase 2: Compiling Vite Production Build"
echo "===================================================="
if [ ! -f ".env" ]; then
  echo "ERROR: .env file missing. API Base URL context injection failed."
  exit 1
fi

npx vite build

echo "===================================================="
echo "☁️ Phase 3: Synchronizing Web Assets to Server Root"
echo "===================================================="
# Clear out historical artifacts from the server web tree
rm -rf /var/www/html/*

# Move newly compiled production static assets into Nginx host directory
cp -r dist/* /var/www/html/

# Correct permissions boundaries so Nginx can read the directory structure
chown -R www-data:www-data /var/www/html
systemctl restart nginx

echo "===================================================="
echo "✅ Execution Engine Pipeline Finished Successfully!"
echo "===================================================="