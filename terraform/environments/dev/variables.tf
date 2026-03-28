variable "aws_region" { type = string }
variable "project_name" {
  type    = string
  default = "cicd-demo"
}
variable "environment" {
  type    = string
  default = "dev"
}
variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}
variable "public_subnet_cidr" {
  type    = string
  default = "10.0.1.0/24"
}
variable "availability_zone" { type = string }
variable "ami_id" { type = string }
variable "key_pair_name" { type = string }
variable "jenkins_instance_type" {
  type    = string
  default = "t3.micro"
}
variable "app_instance_type" {
  type    = string
  default = "t3.micro"
}
variable "allowed_ssh_cidr" { type = string }
