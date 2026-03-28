# Jenkins CI/CD Infrastructure — AWS Provisioning

This repository contains the **Infrastructure as Code (IaC)** for the CI/CD demo project. It uses **Terraform** to provision all required AWS resources and a **Jenkins pipeline** (`Jenkinsfile.infra`) to run Terraform automatically.

Once this pipeline runs successfully, the AWS environment is ready for the backend and frontend application pipelines to deploy into.

---

## Table of Contents

1. [What This Repo Does](#what-this-repo-does)
2. [Architecture Overview](#architecture-overview)
3. [AWS Resources Created](#aws-resources-created)
4. [Repository Structure](#repository-structure)
5. [Prerequisites](#prerequisites)
6. [Step-by-Step Setup Guide](#step-by-step-setup-guide)
   - [Step 1 — AWS Preparation](#step-1--aws-preparation)
   - [Step 2 — Install Terraform Locally (Optional)](#step-2--install-terraform-locally-optional)
   - [Step 3 — Configure terraform.tfvars](#step-3--configure-terraformtfvars)
   - [Step 4 — Set Up Jenkins Credentials](#step-4--set-up-jenkins-credentials)
   - [Step 5 — Create the Jenkins Pipeline](#step-5--create-the-jenkins-pipeline)
   - [Step 6 — Run the Pipeline](#step-6--run-the-pipeline)
7. [Terraform Variables Reference](#terraform-variables-reference)
8. [Security Groups & Port Reference](#security-groups--port-reference)
9. [What Gets Installed on Each EC2](#what-gets-installed-on-each-ec2)
10. [Pipeline Stages Explained](#pipeline-stages-explained)
11. [Terraform Outputs](#terraform-outputs)
12. [How to Destroy the Infrastructure](#how-to-destroy-the-infrastructure)
13. [Troubleshooting](#troubleshooting)
14. [Pipeline Dependency Order](#pipeline-dependency-order)

---

## What This Repo Does

Running the `Jenkinsfile.infra` pipeline in Jenkins will:

1. Check out this repository
2. Run `terraform init` to download the AWS provider
3. Run `terraform plan` to preview what will be created
4. Run `terraform apply` to create all AWS resources
5. Write the public IP addresses of the EC2 instances to disk on the Jenkins server so the application pipelines can use them

---

## Architecture Overview

```
                        ┌─────────────────────────────────────┐
                        │             AWS (us-east-1a)         │
                        │                                      │
                        │   ┌──────────────────────────────┐   │
                        │   │   VPC: 10.0.0.0/16           │   │
                        │   │   Subnet: 10.0.1.0/24        │   │
                        │   │                              │   │
                        │   │  ┌──────────┐                │   │
  Your Machine ─────────┼───┼─▶│ Jenkins  │ t3.medium      │   │
  (SSH only from        │   │  │ :8080    │ 30 GB gp3      │   │
   your IP)             │   │  └──────────┘                │   │
                        │   │                              │   │
                        │   │  ┌──────────┐                │   │
                        │   │  │ Backend  │ t3.small        │   │
                        │   │  │ :8080    │ 20 GB gp3      │   │
                        │   │  └──────────┘                │   │
                        │   │                              │   │
                        │   │  ┌──────────┐                │   │
                        │   │  │Frontend  │ t3.small        │   │
                        │   │  │ :80/:443 │ 20 GB gp3      │   │
                        │   │  └──────────┘                │   │
                        │   └──────────────────────────────┘   │
                        └─────────────────────────────────────┘
```

All three EC2 instances sit in a **public subnet** with an **Internet Gateway** and each has an **Elastic IP** so the address never changes between stops/starts.

---

## AWS Resources Created

| Resource | Details |
|---|---|
| VPC | CIDR `10.0.0.0/16` |
| Public Subnet | CIDR `10.0.1.0/24`, AZ `us-east-1a` |
| Internet Gateway | Attached to the VPC |
| Route Table | Default route `0.0.0.0/0` → IGW |
| Security Group — Jenkins | SSH (your IP only), port 8080 (all), port 50000 (all) |
| Security Group — Backend | SSH (your IP only), port 8080 (all) |
| Security Group — Frontend | SSH (your IP only), port 80 (all), port 443 (all) |
| EC2 — Jenkins | `t3.medium`, Ubuntu, 30 GB, Elastic IP |
| EC2 — Backend | `t3.small`, Ubuntu, 20 GB, Elastic IP |
| EC2 — Frontend | `t3.small`, Ubuntu, 20 GB, Elastic IP |

> **IMDSv2 is enforced** on all EC2 instances (`http_tokens = "required"`) for security.

---

## Repository Structure

```
cicd-boostrap/
├── Jenkinsfile.infra                         # Jenkins pipeline definition
└── terraform/
    ├── environments/
    │   └── dev/
    │       ├── main.tf                       # Calls all modules
    │       ├── variables.tf                  # Variable declarations
    │       ├── outputs.tf                    # EC2 IPs and URLs
    │       ├── terraform.tfvars              # Your environment values
    │       └── user-data/
    │           ├── jenkins-userdata.sh       # Bootstrap script for Jenkins EC2
    │           └── app-userdata.sh           # Bootstrap script for Backend/Frontend EC2s
    └── modules/
        ├── vpc/                              # VPC, subnet, IGW, route table
        ├── security-groups/                  # Three security groups
        └── ec2/                              # Generic EC2 + Elastic IP module
```

---

## Prerequisites

Before you begin, make sure you have the following:

### AWS Account
- An active AWS account
- An **IAM user** with programmatic access (Access Key ID + Secret Access Key) and the following permissions:
  - `AmazonEC2FullAccess`
  - `AmazonVPCFullAccess`

### AWS EC2 Key Pair
- A key pair must already exist in the AWS region you are deploying to (`us-east-1` by default)
- You need the `.pem` private key file on your local machine to SSH into the instances
- If you do not have one, create it in the AWS Console under **EC2 → Key Pairs → Create key pair**

### Jenkins Server
- A running Jenkins server (this pipeline is designed to run **on the Jenkins EC2 it provisions**, but it can also run on any existing Jenkins instance)
- Jenkins version 2.x or later
- The following Jenkins plugins installed:
  - **Pipeline** (usually pre-installed)
  - **Credentials Binding Plugin**
  - **Git Plugin**

### Terraform
- Terraform >= 1.6.0 installed on the Jenkins server (the `jenkins-userdata.sh` script installs this automatically on the Jenkins EC2)

---

## Step-by-Step Setup Guide

### Step 1 — AWS Preparation

1. **Create an IAM User** (if you don't already have one):
   - Go to AWS Console → **IAM** → **Users** → **Create user**
   - Enable **Programmatic access**
   - Attach policies: `AmazonEC2FullAccess` and `AmazonVPCFullAccess`
   - Save the **Access Key ID** and **Secret Access Key** — you will need these in Step 4

2. **Create an EC2 Key Pair** (if you don't already have one):
   - Go to AWS Console → **EC2** → **Key Pairs** → **Create key pair**
   - Choose type **RSA**, format **.pem**
   - Give it a name (e.g. `cicd-demo-key`) — this name goes into `terraform.tfvars`
   - Download and save the `.pem` file securely

3. **Find your public IP address**:
   - Visit [https://checkip.amazonaws.com](https://checkip.amazonaws.com) or run `curl ifconfig.me`
   - Note your IP — you will use it as `x.x.x.x/32` in Step 3 and Step 4

---

### Step 2 — Install Terraform Locally (Optional)

This step is only needed if you want to run Terraform from your own machine instead of Jenkins.

- Download Terraform >= 1.6.0 from [https://developer.hashicorp.com/terraform/downloads](https://developer.hashicorp.com/terraform/downloads)
- Verify: `terraform version`

If you are running this through the Jenkins pipeline, Terraform is installed automatically on the Jenkins EC2 by `jenkins-userdata.sh`.

---

### Step 3 — Configure terraform.tfvars

Open `terraform/environments/dev/terraform.tfvars` and update the values:

```hcl
aws_region            = "us-east-1"
project_name          = "cicd-demo"
environment           = "dev"
vpc_cidr              = "10.0.0.0/16"
public_subnet_cidr    = "10.0.1.0/24"
availability_zone     = "us-east-1a"
ami_id                = "ami-0c7217cdde317cfec"   # Ubuntu 22.04 LTS, us-east-1
key_pair_name         = "your-key-pair-name"       # Name of your EC2 key pair (not the .pem file)
jenkins_instance_type = "t3.medium"
app_instance_type     = "t3.small"
allowed_ssh_cidr      = "YOUR.IP.ADDRESS.HERE/32"  # Your public IP in CIDR format
```

> **Important:** `key_pair_name` is the **name** of the key pair as it appears in the AWS Console, not the path to the `.pem` file.

> **Important:** `allowed_ssh_cidr` restricts SSH access to your IP only. Never set this to `0.0.0.0/0` in production.

> **Note:** `key_pair_name` and `allowed_ssh_cidr` can also be passed as Jenkins credentials (see Step 4) which is the recommended approach so they are never committed to version control.

---

### Step 4 — Set Up Jenkins Credentials

The pipeline reads four secrets from Jenkins credentials. Add them via:

**Jenkins → Manage Jenkins → Credentials → System → Global credentials → Add Credentials**

For each credential, choose **Kind: Secret text**.

| Credential ID | Value |
|---|---|
| `aws-access-key-id` | Your IAM user Access Key ID |
| `aws-secret-access-key` | Your IAM user Secret Access Key |
| `tf-key-pair-name` | Name of your EC2 key pair (e.g. `cicd-demo-key`) |
| `tf-allowed-ssh-cidr` | Your IP in CIDR format (e.g. `1.2.3.4/32`) |

> Credentials are injected at runtime and are **never** stored in the code or logs.

---

### Step 5 — Create the Jenkins Pipeline

1. Go to **Jenkins Dashboard → New Item**
2. Enter a name (e.g. `infra-pipeline`)
3. Select **Pipeline** → Click **OK**
4. Scroll to the **Pipeline** section:
   - **Definition:** Pipeline script from SCM
   - **SCM:** Git
   - **Repository URL:** `https://github.com/ravinderji/jenkins_cicd_infra.git`
   - **Branch:** `*/main` (or your branch name)
   - **Script Path:** `Jenkinsfile.infra`
5. Click **Save**

---

### Step 6 — Run the Pipeline

1. Go to the `infra-pipeline` job
2. Click **Build with Parameters**
3. Leave `DESTROY_INFRA` **unchecked** (default)
4. Click **Build**

The pipeline will run through 4 stages. When it finishes successfully, you will see the public IP addresses of all three EC2 instances printed in the build log:

```
Jenkins  : http://<JENKINS_IP>:8080
Backend  : http://<BACKEND_IP>:8080/api
Frontend : http://<FRONTEND_IP>
```

The IPs are also written to these files on the Jenkins server:
```
/var/lib/jenkins/tf-state/jenkins_ip.txt
/var/lib/jenkins/tf-state/backend_ip.txt
/var/lib/jenkins/tf-state/frontend_ip.txt
```

These files are read automatically by the backend and frontend application pipelines.

---

## Terraform Variables Reference

| Variable | Default | Required | Description |
|---|---|---|---|
| `aws_region` | — | Yes | AWS region to deploy into |
| `project_name` | `cicd-demo` | No | Used as a prefix for all resource names |
| `environment` | `dev` | No | Environment tag (dev/staging/prod) |
| `vpc_cidr` | `10.0.0.0/16` | No | CIDR block for the VPC |
| `public_subnet_cidr` | `10.0.1.0/24` | No | CIDR block for the public subnet |
| `availability_zone` | — | Yes | AZ for the subnet and EC2s |
| `ami_id` | — | Yes | Ubuntu AMI ID for the region |
| `key_pair_name` | — | Yes | Name of existing EC2 key pair |
| `jenkins_instance_type` | `t3.micro` | No | EC2 instance type for Jenkins |
| `app_instance_type` | `t3.micro` | No | EC2 instance type for Backend and Frontend |
| `allowed_ssh_cidr` | — | Yes | Your IP in CIDR format for SSH access |

> The `terraform.tfvars` file overrides the defaults. Values for `key_pair_name` and `allowed_ssh_cidr` are additionally injected by Jenkins credentials at pipeline runtime.

---

## Security Groups & Port Reference

### Jenkins Security Group

| Port | Protocol | Source | Purpose |
|---|---|---|---|
| 22 | TCP | Your IP only | SSH access |
| 8080 | TCP | 0.0.0.0/0 | Jenkins web UI |
| 50000 | TCP | 0.0.0.0/0 | Jenkins JNLP agent communication |

### Backend Security Group

| Port | Protocol | Source | Purpose |
|---|---|---|---|
| 22 | TCP | Your IP only | SSH access |
| 8080 | TCP | 0.0.0.0/0 | Spring Boot API |

### Frontend Security Group

| Port | Protocol | Source | Purpose |
|---|---|---|---|
| 22 | TCP | Your IP only | SSH access |
| 80 | TCP | 0.0.0.0/0 | HTTP (nginx) |
| 443 | TCP | 0.0.0.0/0 | HTTPS (nginx) |

All security groups allow all outbound traffic.

---

## What Gets Installed on Each EC2

### Jenkins EC2 (via `jenkins-userdata.sh`)

The bootstrap script runs automatically on first launch and installs:

| Tool | Purpose |
|---|---|
| Java 17 (OpenJDK) | Required by Jenkins and Maven builds |
| Jenkins (LTS) | CI/CD server |
| Docker + Docker Compose | Container builds and deployments |
| Maven | Build tool for the Spring Boot backend |
| Node.js 20 | Build tool for the React frontend |
| Ansible + community.docker | Configuration management for app deployments |
| Terraform | Infrastructure provisioning (for this pipeline) |

> The `ubuntu` and `jenkins` users are both added to the `docker` group.
> The script logs all output to `/var/log/userdata.log` on the instance.

### Backend & Frontend EC2s (via `app-userdata.sh`)

| Tool | Purpose |
|---|---|
| Docker + Docker Compose | Runs the application containers |

> These are minimal servers — everything runs inside Docker containers managed by Ansible.

---

## Pipeline Stages Explained

| Stage | What Happens |
|---|---|
| **Stage 1 — Checkout** | Clones this repo and prints the git commit and branch |
| **Stage 2 — Terraform Init** | Downloads the AWS Terraform provider; uses `-reconfigure` for a clean state on each run |
| **Stage 3 — Terraform Plan** | Generates an execution plan showing exactly what AWS resources will be created or changed; saves the plan as a build artifact (`tfplan.txt`) |
| **Stage 4 — Terraform Apply** | Creates all AWS resources; reads the output IPs and writes them to `/var/lib/jenkins/tf-state/` |
| **Stage 5 — Terraform Destroy** | Only runs when `DESTROY_INFRA=true`; deletes all AWS resources and removes the IP files |

---

## Terraform Outputs

After a successful apply, the following values are available:

| Output | Description |
|---|---|
| `jenkins_public_ip` | Elastic IP of the Jenkins EC2 |
| `backend_public_ip` | Elastic IP of the Backend EC2 |
| `frontend_public_ip` | Elastic IP of the Frontend EC2 |
| `jenkins_url` | `http://<jenkins_ip>:8080` |
| `backend_api_url` | `http://<backend_ip>:8080/api` |
| `frontend_url` | `http://<frontend_ip>` |

View outputs at any time by running inside `terraform/environments/dev/`:
```bash
terraform output
```

---

## How to Destroy the Infrastructure

To delete **all** AWS resources created by this pipeline:

1. Go to the `infra-pipeline` Jenkins job
2. Click **Build with Parameters**
3. **Check** the `DESTROY_INFRA` checkbox
4. Click **Build**

The pipeline will run a `terraform destroy`, delete all EC2 instances, security groups, subnet, VPC, and Elastic IPs, and clean up the IP files from the Jenkins server.

> **Warning:** This action is irreversible. All running application containers will be terminated.

---

## Troubleshooting

### Terraform init fails — "Failed to query available provider packages"
The Jenkins EC2 cannot reach the internet. Check that the VPC has an Internet Gateway and the route table is correctly associated with the public subnet.

### Terraform apply fails — "Error: Unauthorized"
Your AWS credentials are incorrect or the IAM user does not have the required permissions. Verify the `aws-access-key-id` and `aws-secret-access-key` Jenkins credentials.

### Terraform apply fails — "InvalidKeyPair.NotFound"
The key pair name in `tf-key-pair-name` does not exist in the target AWS region. Create the key pair in the AWS Console first.

### EC2 instances are created but Jenkins is not accessible on port 8080
The `jenkins-userdata.sh` bootstrap script can take 5–10 minutes to complete. SSH into the Jenkins EC2 and run:
```bash
cat /var/log/userdata.log
```
Wait for the line `=== Jenkins Bootstrap COMPLETE ===` to appear.

### How to find the Jenkins initial admin password
SSH into the Jenkins EC2 and run:
```bash
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

### App pipelines fail with "No such file: backend_ip.txt"
The infra pipeline has not been run yet, or it failed. Run `infra-pipeline` first and ensure it completes successfully before running the application pipelines.

---

## Pipeline Dependency Order

This repo is **Step 1** of a three-pipeline workflow. The pipelines must be run in order:

```
1. infra-pipeline          ← This repo (provisions AWS infrastructure)
        │
        ▼
2. backend-app-pipeline    ← github.com/ravinderji/jenkins_cicd_backend
        │
        ▼
3. frontend-app-pipeline   ← github.com/ravinderji/jenkins_cicd_frontend
```

The backend and frontend pipelines read the IP files written to `/var/lib/jenkins/tf-state/` by this pipeline. They will fail if this pipeline has not run first.
