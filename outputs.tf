output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.devbox.id
}

output "tailscale_hostname" {
  description = "Tailscale hostname for SSH access"
  value       = var.tailscale_hostname
}

output "ssh_command" {
  description = "SSH command to connect (via Tailscale)"
  value       = "ssh ${var.tailscale_hostname}"
}

output "vscode_remote" {
  description = "VS Code Remote SSH config entry"
  value       = <<-EOT
    Host ${var.tailscale_hostname}
        HostName ${var.tailscale_hostname}
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

output "instance_type" {
  description = "Instance type"
  value       = var.instance_type
}

output "spot_enabled" {
  description = "Whether spot pricing is enabled"
  value       = var.use_spot
}

output "pricing_estimate" {
  description = "Estimated hourly cost"
  value       = var.use_spot ? "~$0.06/hr (spot)" : "~$0.20/hr (on-demand)"
}

output "volumes" {
  description = "EBS volumes"
  value = {
    root = "${var.volume_size}GB (OS, tools)"
    data = "${var.data_volume_size}GB (LUKS encrypted /home)"
  }
}
