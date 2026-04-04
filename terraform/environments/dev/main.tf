terraform {
 required_version = ">= 1.6.0"
 required_providers {
  aws = {
    source  = "hashicorp/aws"
    version = "~> 5.0"
  }
 }
 backend "s3" {
   bucket = "cicd-demo-tfstate-058264484175"
   key    = "dev/terraform.tfstate"
   region = "us-east-1"
 }
}

provider "aws" { region = var.aws_region }

module "vpc" {
 source = "../../modules/vpc"
 project_name = var.project_name
 environment = var.environment
 vpc_cidr = var.vpc_cidr
 public_subnet_cidr = var.public_subnet_cidr
 availability_zone = var.availability_zone
}

module "security_groups" {
 source = "../../modules/security-groups"
 project_name = var.project_name
 environment = var.environment
 vpc_id = module.vpc.vpc_id
 allowed_ssh_cidr = var.allowed_ssh_cidr
}

module "jenkins_ec2" {
 source = "../../modules/ec2"
 project_name = var.project_name
 environment = var.environment
 instance_name = "jenkins"
 instance_type = var.jenkins_instance_type
 ami_id = var.ami_id
 subnet_id = module.vpc.public_subnet_id
 security_group_ids = [module.security_groups.jenkins_sg_id]
 key_name = var.key_pair_name
 user_data = file("${path.module}/user-data/jenkins-userdata.sh")
 root_volume_size = 30
}

module "backend_ec2" {
 source = "../../modules/ec2"
 project_name = var.project_name
 environment = var.environment
 instance_name = "backend"
 instance_type = var.app_instance_type
 ami_id = var.ami_id
 subnet_id = module.vpc.public_subnet_id
 security_group_ids = [module.security_groups.backend_sg_id]
 key_name = var.key_pair_name
 user_data = file("${path.module}/user-data/app-userdata.sh")
 root_volume_size =  20
}

module "frontend_ec2" {
   source             = "../../modules/ec2"
  project_name       = var.project_name
  environment        = var.environment
  instance_name      = "frontend"
  instance_type      = var.app_instance_type
  ami_id             = var.ami_id
  subnet_id          = module.vpc.public_subnet_id
  security_group_ids = [module.security_groups.frontend_sg_id]
  key_name           = var.key_pair_name
  user_data          = file("${path.module}/user-data/app-userdata.sh")
  root_volume_size   = 20
}
