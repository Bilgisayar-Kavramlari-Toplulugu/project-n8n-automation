terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  # GitHub Actions icin Remote State (S3)
  # NOT: Bu bucket ve DynamoDB tablosunu manuel olusturmaniz gerekir.
  backend "s3" {
    bucket         = "n8n-terraform-state-2026"
    key            = "terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.region
}

# ─────────────────────────────────────────
# 1. VPC
# ─────────────────────────────────────────
resource "aws_vpc" "main_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = { Name = "main-vpc" }
}

# ─────────────────────────────────────────
# 2. Public Subnet
# ─────────────────────────────────────────
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.region}a"
  tags                    = { Name = "public-subnet" }
}

# ─────────────────────────────────────────
# 3. Internet Gateway
# ─────────────────────────────────────────
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main_vpc.id
  tags   = { Name = "main-igw" }
}

# ─────────────────────────────────────────
# 4. Route Table
# ─────────────────────────────────────────
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "public-route-table" }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# ─────────────────────────────────────────
# 5. Security Group
# ─────────────────────────────────────────
resource "aws_security_group" "allow_web" {
  name        = "allow_web_traffic"
  description = "Caddy reverse proxy portlari"
  vpc_id      = aws_vpc.main_vpc.id

  dynamic "ingress" {
    for_each = toset(var.ssh_allowed_cidrs)
    content {
      description = "SSH - restricted CIDR"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  ingress {
    description = "HTTP - Caddy reverse proxy to N8N"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS - Caddy auto SSL if domain set"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "allow_web" }
}

# ─────────────────────────────────────────
# 6. SSH Key Pair
# ─────────────────────────────────────────
resource "aws_key_pair" "app_key" {
  count      = trimspace(var.ssh_public_key) == "" ? 0 : 1
  key_name   = var.key_name
  public_key = var.ssh_public_key
}

# ─────────────────────────────────────────
# 7. AMI - Ubuntu 22.04
# ─────────────────────────────────────────
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ─────────────────────────────────────────
# 8. EC2 Instance
#    user_data_replace_on_change = true
#    => user_data degisince instance otomatik yeniden kurulur
#    => sadece terraform apply yeter
# ─────────────────────────────────────────
resource "aws_instance" "app_server" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  key_name                    = length(aws_key_pair.app_key) == 0 ? null : aws_key_pair.app_key[0].key_name
  user_data_replace_on_change = true

  lifecycle {
    precondition {
      condition     = length(var.ssh_allowed_cidrs) == 0 || trimspace(var.ssh_public_key) != ""
      error_message = "ssh_public_key must be set when ssh_allowed_cidrs is not empty."
    }
  }

  dynamic "instance_market_options" {
    for_each = var.use_spot_instance ? [1] : []
    content {
      market_type = "spot"
      spot_options {
        spot_instance_type             = "persistent"
        instance_interruption_behavior = "stop"
      }
    }
  }

  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.allow_web.id]

  credit_specification {
    cpu_credits = "standard"
  }

  user_data = join("\n", [
    file("${path.module}/scripts/00-setup-swap.sh"),
    file("${path.module}/scripts/01-install-docker.sh"),
    templatefile("${path.module}/scripts/02-deploy-stack.sh", {
      n8n_password = jsonencode(var.n8n_password)
    }),
    templatefile("${path.module}/scripts/03-security-hardening.sh", {
      enable_ssh = length(var.ssh_allowed_cidrs) > 0
    })
  ])

  tags = { Name = "n8n-caddy-server" }
}

# # ─────────────────────────────────────────
# # 9. Elastic IP - Sabit IP, hic degismez
# # ─────────────────────────────────────────
# resource "aws_eip" "app_eip" {
#   instance = aws_instance.app_server.id
#   domain   = "vpc"
#   tags     = { Name = "n8n-elastic-ip" }
# }
