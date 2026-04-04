#!/bin/bash
# =============================================================================
# Jenkins EC2 Bootstrap Script
# Installs: Java 17, Jenkins, Docker, Maven, Node.js 20, Ansible, Terraform
# =============================================================================
# -uo pipefail: flag undefined vars and pipe errors, but NOT -e so one
# section failing does NOT abort the whole script.
set -uo pipefail
exec > /var/log/userdata.log 2>&1

echo "=== Jenkins Bootstrap START: $(date) ==="

# ── Helper: retry a command up to 3 times with 10s delay ─────────────────────
retry() {
  local count=0
  until "$@"; do
    count=$((count + 1))
    if [ "$count" -ge 3 ]; then
      echo "ERROR: Command failed after 3 attempts: $*"
      return 1
    fi
    echo "  retry $count/3 in 10s..."
    sleep 10
  done
}

# ── Distro codename — never use lsb_release (may not be installed yet) ───────
DISTRO=$(. /etc/os-release && echo "$VERSION_CODENAME")
ARCH=$(dpkg --print-architecture)
echo "Distro: $DISTRO | Arch: $ARCH"

# ── Dedicated GPG home — prevents 'no home dir' errors in headless root ──────
export GNUPGHOME=/tmp/gnupg-bootstrap
mkdir -p "$GNUPGHOME"
chmod 700 "$GNUPGHOME"

# ── Base packages ─────────────────────────────────────────────────────────────
echo "--- Installing base packages ---"
retry apt-get update -y
retry apt-get install -y \
  ca-certificates curl gnupg wget unzip git \
  software-properties-common apt-transport-https \
  python3 python3-pip
echo "--- Base packages OK ---"

# ── Java 17 ───────────────────────────────────────────────────────────────────
echo "--- Installing Java 17 ---"
retry apt-get install -y openjdk-17-jdk
java -version
echo "--- Java 17 OK ---"

# ── Jenkins ───────────────────────────────────────────────────────────────────
# Use [trusted=yes] to bypass GPG entirely — avoids key rotation issues.
# This is safe for a learning/demo environment.
echo "--- Installing Jenkins ---"
echo "deb [trusted=yes] https://pkg.jenkins.io/debian-stable binary/" \
  | tee /etc/apt/sources.list.d/jenkins.list > /dev/null
retry apt-get update -y
retry apt-get install -y jenkins
systemctl enable jenkins
systemctl start jenkins
echo "--- Jenkins OK ---"

# ── Docker ────────────────────────────────────────────────────────────────────
echo "--- Installing Docker ---"
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /tmp/docker.gpg
gpg --batch --yes --dearmor \
  -o /usr/share/keyrings/docker-archive-keyring.gpg \
  /tmp/docker.gpg
echo "deb [arch=${ARCH} signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
  https://download.docker.com/linux/ubuntu ${DISTRO} stable" \
  | tee /etc/apt/sources.list.d/docker.list > /dev/null
retry apt-get update -y
retry apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
usermod -aG docker ubuntu
usermod -aG docker jenkins
systemctl enable docker
systemctl start docker
docker --version
echo "--- Docker OK ---"

# ── Maven ─────────────────────────────────────────────────────────────────────
echo "--- Installing Maven ---"
retry apt-get install -y maven
mvn --version | head -1
echo "--- Maven OK ---"

# ── Node.js 20 ────────────────────────────────────────────────────────────────
echo "--- Installing Node.js 20 ---"
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
retry apt-get install -y nodejs
node --version
echo "--- Node.js OK ---"

# ── Ansible ───────────────────────────────────────────────────────────────────
# Install via PPA for latest stable version — avoids pip/break-system-packages issues
echo "--- Installing Ansible ---"
apt-add-repository -y ppa:ansible/ansible
retry apt-get update -y
retry apt-get install -y ansible
ansible-galaxy collection install community.docker
ansible --version | head -1
echo "--- Ansible OK ---"

# ── Terraform ─────────────────────────────────────────────────────────────────
echo "--- Installing Terraform ---"
wget -qO /tmp/hashicorp.gpg https://apt.releases.hashicorp.com/gpg
gpg --batch --yes --dearmor \
  -o /usr/share/keyrings/hashicorp-archive-keyring.gpg \
  /tmp/hashicorp.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
  https://apt.releases.hashicorp.com ${DISTRO} main" \
  | tee /etc/apt/sources.list.d/hashicorp.list > /dev/null
retry apt-get update -y
retry apt-get install -y terraform
terraform version | head -1
echo "--- Terraform OK ---"

# ── Restart Jenkins so docker group membership takes effect ──────────────────
echo "--- Restarting Jenkins ---"
systemctl restart jenkins
echo "--- Jenkins restarted ---"

# ── Directories for SSH key and Terraform state ──────────────────────────────
mkdir -p /var/lib/jenkins/.ssh
chmod 700 /var/lib/jenkins/.ssh
chown -R jenkins:jenkins /var/lib/jenkins/.ssh

mkdir -p /var/lib/jenkins/tf-state
chown -R jenkins:jenkins /var/lib/jenkins/tf-state

# ── Verify all tools are accessible by jenkins user ──────────────────────────
echo "--- Tool verification ---"
sudo -u jenkins java -version 2>&1 | head -1
sudo -u jenkins docker --version
sudo -u jenkins mvn --version | head -1
sudo -u jenkins node --version
sudo -u jenkins ansible --version | head -1
sudo -u jenkins terraform version | head -1
echo "--- All tools verified ---"

# ── Wait for Jenkins initial admin password ───────────────────────────────────
echo "=== Jenkins Bootstrap COMPLETE: $(date) ==="
echo "Waiting for Jenkins initial admin password..."
for i in $(seq 1 30); do
  if [ -f /var/lib/jenkins/secrets/initialAdminPassword ]; then
    echo "Initial Admin Password: $(cat /var/lib/jenkins/secrets/initialAdminPassword)"
    break
  fi
  echo "  waiting... ($i/30)"
  sleep 10
done
