resource "aws_instance" "this" {
 ami = var.ami_id
 instance_type = var.instance_type
 subnet_id = var.subnet_id
 vpc_security_group_ids = var.security_group_ids
 key_name = var.key_name
 user_data = var.user_data
 
 root_block_device {
  volume_type = "gp3"
  volume_size = var.root_volume_size
  delete_on_termination = true
  encrypted = false
 }

 metadata_options { http_tokens = "required" }
 
 tags = {
  Name = "${var.project_name}-${var.environment}-${var.instance_name}"
  Role = var.instance_name
  Project = var.project_name
  Environment = var.environment
  ManagedBy = "Terraform"
 } 
 
 lifecycle { ignore_changes = [user_data] }
 }

