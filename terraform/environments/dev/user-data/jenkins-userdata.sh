#!/bin/bash
# =============================================================================
# Jenkins EC2 Bootstrap Script
# Installs: Java 17, Jenkins, Docker, Maven, Node.js 20, Ansible, Terraform
# =============================================================================
set -euo pipefail
exec > /var/log/userdata.log 2>&1

echo "=== Jenkins Bootstrap START: $(date) ==="

# ── Helper: retry a command up to 3 times with 10s delay ─────────────────────
retry() {
  local attempts=3
  local delay=10
  local count=0
  until "$@"; do
    count=$((count + 1))
    if [ "$count" -ge "$attempts" ]; then
      echo "ERROR: Command failed after $attempts attempts: $*"
      return 1
    fi
    echo "Attempt $count/$attempts failed — retrying in ${delay}s..."
    sleep "$delay"
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
retry apt-get update -y
retry apt-get install -y \
  ca-certificates curl gnupg wget unzip git \
  software-properties-common apt-transport-https \
  python3 python3-pip

# ── Java 17 ───────────────────────────────────────────────────────────────────
echo "--- Installing Java 17 ---"
retry apt-get install -y openjdk-17-jdk
java -version

# ── Jenkins ───────────────────────────────────────────────────────────────────
# Fetch signing key by exact fingerprint from keyserver — the jenkins.io-2023.key
# URL contains a DIFFERENT key that does not match the repo's Release.gpg signature.
# Fingerprint 5E386EADB55F01504CAE8BCF7198F4B714ABFC68 is the actual signing key.
echo "--- Installing Jenkins ---"
gpg --batch --keyserver hkp://keyserver.ubuntu.com:80 \
  --recv-keys 5E386EADB55F01504CAE8BCF7198F4B714ABFC68
gpg --batch --export 5E386EADB55F01504CAE8BCF7198F4B714ABFC68 \
  > /usr/share/keyrings/jenkins-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.gpg] \
  https://pkg.jenkins.io/debian-stable binary/" \
  | tee /etc/apt/sources.list.d/jenkins.list > /dev/null
retry apt-get update -y
retry apt-get install -y jenkins
systemctl enable jenkins
systemctl start jenkins
echo "Jenkins installed OK"

# ── Docker ────────────────────────────────────────────────────────────────────
# Use file-based gpg --dearmor (not stdin redirect) with explicit output path
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

# ── Maven ─────────────────────────────────────────────────────────────────────
echo "--- Installing Maven ---"
retry apt-get install -y maven
mvn --version | head -1

# ── Node.js 20 ────────────────────────────────────────────────────────────────
echo "--- Installing Node.js 20 ---"
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
retry apt-get install -y nodejs
node --version

# ── Ansible ───────────────────────────────────────────────────────────────────
echo "--- Installing Ansible ---"
pip3 install --quiet ansible --break-system-packages
sudo -u jenkins ansible-galaxy collection install community.docker
ansible --version | head -1

# ── Terraform ─────────────────────────────────────────────────────────────────
# Use file-based gpg --dearmor with explicit output path
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

# ── Restart Jenkins so docker group membership takes effect ──────────────────
echo "--- Restarting Jenkins ---"
systemctl restart jenkins

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
