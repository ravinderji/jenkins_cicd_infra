#!/bin/bash
set -euo pipefail
exec > /var/log/userdata.log 2>&1
echo "=== Jenkins Bootstrap START ==="

apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release wget unzip git software-properties-common

# Java 17
apt-get install -y openjdk-17-jdk

# Jenkins - import signing key by fingerprint (URL-based keys can rotate/expire)
gpg --batch --keyserver hkp://keyserver.ubuntu.com:80 \
  --recv-keys 5E386EADB55F01504CAE8BCF7198F4B714ABFC68
gpg --batch --export 5E386EADB55F01504CAE8BCF7198F4B714ABFC68 \
  > /usr/share/keyrings/jenkins-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.gpg] \
  https://pkg.jenkins.io/debian-stable binary/" \
  | tee /etc/apt/sources.list.d/jenkins.list > /dev/null
apt-get update -y && apt-get install -y jenkins

systemctl enable jenkins && systemctl start jenkins

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
usermod -aG docker jenkins
systemctl enable docker && systemctl start docker

# Maven
apt-get install -y maven

# Node.js 20
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

# Ansible
apt-get install -y python3 python3-pip
pip3 install ansible --break-system-packages
sudo -u jenkins ansible-galaxy collection install community.docker

# Terraform
wget -O- https://apt.releases.hashicorp.com/gpg \
  | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
  https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
  | tee /etc/apt/sources.list.d/hashicorp.list > /dev/null
apt-get update -y && apt-get install -y terraform

# Restart Jenkins so docker group takes effect
systemctl restart jenkins

# Directories for deploy key and Terraform state
mkdir -p /var/lib/jenkins/.ssh
chmod 700 /var/lib/jenkins/.ssh
chown -R jenkins:jenkins /var/lib/jenkins/.ssh
mkdir -p /var/lib/jenkins/tf-state
chown -R jenkins:jenkins /var/lib/jenkins/tf-state

echo "=== Jenkins Bootstrap COMPLETE ==="
echo "Waiting for Jenkins to generate initial admin password..."
for i in $(seq 1 30); do
  if [ -f /var/lib/jenkins/secrets/initialAdminPassword ]; then
    echo "Initial Admin Password:"
    cat /var/lib/jenkins/secrets/initialAdminPassword
    break
  fi
  sleep 10
done
