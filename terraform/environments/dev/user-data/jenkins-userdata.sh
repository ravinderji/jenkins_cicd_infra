#!/bin/bash
set -euo pipefail
exec > /var/log/userdata.log 2>&1
echo "=== Jenkins Bootstrap START ==="

apt-get update -y
apt-get install -y ca-certificates curl gnupg wget unzip git software-properties-common

# Distro codename — read from /etc/os-release (works reliably in userdata without lsb_release)
DISTRO=$(. /etc/os-release && echo "$VERSION_CODENAME")
echo "Detected distro codename: $DISTRO"

# Java 17
apt-get install -y openjdk-17-jdk

# Jenkins — download key to file first, then dearmor (avoids corrupt keyring from broken pipe)
wget -qO /tmp/jenkins.gpg https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key
gpg --dearmor < /tmp/jenkins.gpg > /usr/share/keyrings/jenkins-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.gpg] \
  https://pkg.jenkins.io/debian-stable binary/" \
  | tee /etc/apt/sources.list.d/jenkins.list > /dev/null
apt-get update -y && apt-get install -y jenkins

systemctl enable jenkins && systemctl start jenkins

# Docker — download key to file first, then dearmor
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /tmp/docker.gpg
gpg --dearmor < /tmp/docker.gpg > /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) \
  signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
  https://download.docker.com/linux/ubuntu ${DISTRO} stable" \
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

# Terraform — download key to file first, then dearmor
wget -qO /tmp/hashicorp.gpg https://apt.releases.hashicorp.com/gpg
gpg --dearmor < /tmp/hashicorp.gpg > /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
  https://apt.releases.hashicorp.com ${DISTRO} main" \
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
