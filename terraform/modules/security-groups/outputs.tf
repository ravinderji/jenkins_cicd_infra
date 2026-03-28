output "jenkins_sg_id" { value = aws_security_group.jenkins.id }
output "backend_sg_id" { value = aws_security_group.backend.id }
output "frontend_sg_id" { value = aws_security_group.frontend.id }
