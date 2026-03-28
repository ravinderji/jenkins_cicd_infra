#!/bin/bash
set -euo pipefail
exec > /var/log/userdata.log 2>&1
echo "=== App Server Bootstrap START ==="

apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release python3 python3-pip

# Docker
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) \
  signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
usermod -aG docker ubuntu
systemctl enable docker && systemctl start docker

echo "=== App Server Bootstrap COMPLETE ==="

