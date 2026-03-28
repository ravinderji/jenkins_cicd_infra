output "jenkins_public_ip"  { value = module.jenkins_ec2.public_ip }
output "backend_public_ip"  { value = module.backend_ec2.public_ip }
output "frontend_public_ip" { value = module.frontend_ec2.public_ip }
output "jenkins_url"        { value = "http://${module.jenkins_ec2.public_ip}:8080" }
output "backend_api_url"    { value = "http://${module.backend_ec2.public_ip}:8080/api" }
output "frontend_url"       { value = "http://${module.frontend_ec2.public_ip}" }
