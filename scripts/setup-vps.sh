#!/usr/bin/env bash
# =============================================================================
# scripts/setup-vps.sh — One-time setup script for a fresh Ubuntu 24.04 VPS
# =============================================================================

set -euo pipefail

# Repository URL for cloning
REPO_URL="https://github.com/Anshul-exe/FastAPI-Redis-Stack.git"

echo "Updating and upgrading packages..."
apt-get update
apt-get upgrade -y

echo "Installing required packages..."
apt-get install -y docker.io docker-compose-plugin git curl ufw

echo "Adding ubuntu user to docker group..."
usermod -aG docker ubuntu

echo "Configuring UFW firewall..."
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

echo "Creating Postgres backup directory..."
mkdir -p /opt/backups/postgres/
chown -R ubuntu:ubuntu /opt/backups/postgres/

echo "Cloning the repository..."
if [ ! -d "/opt/taskapi" ]; then
  git clone "$REPO_URL" /opt/taskapi/
else
  echo "Directory /opt/taskapi already exists. Skipping clone."
fi
chown -R ubuntu:ubuntu /opt/taskapi/

echo "===================================================================="
echo "VPS Provisioning Complete!"
echo "Next manual steps for the operator:"
echo "1. Log out and log back in to apply the 'docker' group permissions."
echo "2. cd /opt/taskapi/ && cp .env.example .env and fill in real values."
echo "3. Follow docs/deployment.md to bootstrap the SSL cert and start the stack."
echo "4. Set up the automated backup cron job."
echo "5. Add GitHub Secrets to enable CI/CD."
echo "===================================================================="
