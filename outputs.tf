output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.devbox.id
}

output "public_ip" {
  description = "Elastic IP address (static)"
  value       = aws_eip.devbox.public_ip
}

output "ssh_command" {
  description = "SSH command to connect"
  value       = "ssh ubuntu@${aws_eip.devbox.public_ip}"
}

output "vscode_remote" {
  description = "VS Code Remote SSH config entry"
  value       = <<-EOT
    Host devbox
        HostName ${aws_eip.devbox.public_ip}
        User ubuntu
        IdentityFile ~/.ssh/your-key
  EOT
}

output "ami_id" {
  description = "Ubuntu AMI used"
  value       = data.aws_ami.ubuntu.id
}

output "ami_name" {
  description = "Ubuntu AMI name"
  value       = data.aws_ami.ubuntu.name
}
