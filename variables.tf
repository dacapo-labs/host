variable "aws_region" {
  description = "AWS region to deploy the devbox"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type - m7a.xlarge recommended for reliable dev work"
  type        = string
  default     = "m7a.xlarge"
}

variable "volume_size" {
  description = "Root EBS volume size in GB"
  type        = number
  default     = 100
}

variable "volume_iops" {
  description = "EBS gp3 IOPS (3000 is baseline)"
  type        = number
  default     = 3000
}

variable "volume_throughput" {
  description = "EBS gp3 throughput in MiB/s (default 125, recommended 250)"
  type        = number
  default     = 250
}

variable "hostname" {
  description = "Hostname for the devbox"
  type        = string
  default     = "aws-dev-box"
}

variable "ssh_public_key" {
  description = "SSH public key for access"
  type        = string
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed to SSH (use your IP/32 for security)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "snapshot_retention_days" {
  description = "Number of days to retain daily EBS snapshots"
  type        = number
  default     = 7
}
