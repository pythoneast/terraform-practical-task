terraform {
  required_version = ">= 1.0"
  backend "s3" {}
}

provider "aws" {
  region = var.region
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "3.11.0"

  name = "eMASE"
  cidr = "10.0.0.0/16"

  azs             = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway = true
  enable_vpn_gateway = true
  enable_ipv6        = false
}

resource "aws_security_group" "lb_public_access" {
  name        = "lb-public-access"
  vpc_id      = module.vpc.vpc_id
  description = "Security group for Load Balancer"

  ingress {
    from_port = 80
    to_port   = 80
    protocol  = "tcp"
    cidr_blocks = [
      "0.0.0.0/0"
    ]
  }

  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = module.vpc.private_subnets_cidr_blocks
  }
}

resource "aws_security_group" "ec2_lb_access" {
  name        = "ec2-lb-access"
  vpc_id      = module.vpc.vpc_id
  description = "Security group for EC2 instances"

  ingress {
    from_port = 80
    to_port   = 80
    protocol  = "tcp"
    security_groups = [
      aws_security_group.lb_public_access.id
    ]
  }

  egress {
    from_port = 80
    to_port   = 80
    protocol  = "tcp"
    cidr_blocks = [
      "0.0.0.0/0"
    ]
  }
}

resource "aws_instance" "app" {
  count         = 2
  ami           = var.ami_id
  instance_type = "t3.micro"
  subnet_id     = module.vpc.private_subnets[count.index % length(module.vpc.private_subnets)]

  vpc_security_group_ids = [
    aws_security_group.ec2_lb_access.id
  ]
  associate_public_ip_address = false

  user_data = <<-EOF
    #!/bin/sh
    apt-get update
    apt-get install -y nginx-light
    echo 'Hello from instance app-${count.index}' > /var/www/html/index.html
  EOF

  tags = {
    "Name" = "app-${count.index}"
  }
}
