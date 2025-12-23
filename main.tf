# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------

resource "aws_vpc" "devbox" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "devbox-vpc"
  }
}

resource "aws_subnet" "devbox" {
  vpc_id                  = aws_vpc.devbox.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "devbox-subnet"
  }
}

resource "aws_internet_gateway" "devbox" {
  vpc_id = aws_vpc.devbox.id

  tags = {
    Name = "devbox-igw"
  }
}

resource "aws_route_table" "devbox" {
  vpc_id = aws_vpc.devbox.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.devbox.id
  }

  tags = {
    Name = "devbox-rt"
  }
}

resource "aws_route_table_association" "devbox" {
  subnet_id      = aws_subnet.devbox.id
  route_table_id = aws_route_table.devbox.id
}

# -----------------------------------------------------------------------------
# Security Group
# -----------------------------------------------------------------------------

resource "aws_security_group" "devbox" {
  name        = "devbox-sg"
  description = "Security group for devbox instance"
  vpc_id      = aws_vpc.devbox.id

  # SSH access
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "devbox-sg"
  }
}

# -----------------------------------------------------------------------------
# SSH Key Pair
# -----------------------------------------------------------------------------

resource "aws_key_pair" "devbox" {
  key_name   = "devbox-key"
  public_key = var.ssh_public_key
}

# -----------------------------------------------------------------------------
# EC2 Instance
# -----------------------------------------------------------------------------

resource "aws_instance" "devbox" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.devbox.key_name
  subnet_id              = aws_subnet.devbox.id
  vpc_security_group_ids = [aws_security_group.devbox.id]

  root_block_device {
    volume_size           = var.volume_size
    volume_type           = "gp3"
    iops                  = var.volume_iops
    throughput            = var.volume_throughput
    delete_on_termination = false
    encrypted             = true

    tags = {
      Name = "devbox-root"
    }
  }

  user_data = templatefile("${path.module}/scripts/user-data.sh", {
    hostname = var.hostname
  })

  # Don't recreate instance if user-data changes
  lifecycle {
    ignore_changes = [user_data]
  }

  tags = {
    Name = var.hostname
  }
}

# -----------------------------------------------------------------------------
# Elastic IP (static address)
# -----------------------------------------------------------------------------

resource "aws_eip" "devbox" {
  instance = aws_instance.devbox.id
  domain   = "vpc"

  tags = {
    Name = "devbox-eip"
  }
}

# -----------------------------------------------------------------------------
# DLM Snapshot Policy (Daily backups)
# -----------------------------------------------------------------------------

resource "aws_iam_role" "dlm" {
  name = "devbox-dlm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "dlm.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "dlm" {
  role       = aws_iam_role.dlm.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSDataLifecycleManagerServiceRole"
}

resource "aws_dlm_lifecycle_policy" "devbox" {
  description        = "Daily snapshots for devbox volume"
  execution_role_arn = aws_iam_role.dlm.arn
  state              = "ENABLED"

  policy_details {
    resource_types = ["VOLUME"]

    schedule {
      name = "Daily snapshots"

      create_rule {
        interval      = 24
        interval_unit = "HOURS"
        times         = ["03:00"] # 3 AM UTC
      }

      retain_rule {
        count = var.snapshot_retention_days
      }

      tags_to_add = {
        SnapshotCreator = "DLM"
        Project         = "aws-devbox"
      }

      copy_tags = true
    }

    target_tags = {
      Name = "devbox-root"
    }
  }

  tags = {
    Name = "devbox-dlm-policy"
  }
}
