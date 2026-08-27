# =================================================================
# FRONTEND DEPLOYMENT STORAGE TIER
# =================================================================
resource "aws_s3_bucket" "frontend_staging" {
  bucket        = "micro-netflix-frontend-staging-dal"
  force_destroy = true
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "frontend_site" {
  bucket        = "${var.project_name}-frontend-site-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "frontend_site_public_access" {
  bucket = aws_s3_bucket.frontend_site.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_ownership_controls" "frontend_site_ownership" {
  bucket = aws_s3_bucket.frontend_site.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_website_configuration" "frontend_site_website" {
  bucket = aws_s3_bucket.frontend_site.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "index.html"
  }
}

resource "aws_s3_bucket_policy" "frontend_site_public_read" {
  bucket = aws_s3_bucket.frontend_site.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadForStaticWebsite"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.frontend_site.arn}/*"
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.frontend_site_public_access]
}

# =================================================================
# COMPUTE TIER (FRONTEND WEB SERVICE & DEPLOYMENT ENGINE)
# =================================================================

# Security Group for Public Web Traffic
resource "aws_security_group" "frontend_sg" {
  name        = "micro-netflix-frontend-sg"
  description = "Allow inbound public HTTP access"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP Traffic"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "micro-netflix-frontend-sg" }
}

# EC2 Instance Hosting the React Application
resource "aws_instance" "frontend_server" {
  ami                    = "ami-053b0d53c279acc90" # Ubuntu 22.04 LTS in us-east-1
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.frontend_sg.id]
  iam_instance_profile   = "LabInstanceProfile"

  user_data = <<-EOF
              #!/bin/bash
              set -e
              
              # 1. Allocate 2GB of Swap Space to prevent Vite/NPM memory crashes on t2.micro
              fallocate -l 2G /swapfile
              chmod 600 /swapfile
              mkswap /swapfile
              swapon /swapfile
              echo '/swapfile none swap sw 0 0' >> /etc/fstab

              # 2. Update package mirrors and install dependencies
              apt-get update -y
              apt-get install -y nginx ruby-full wget python3-pip curl
              
              # 3. Pull and configure Node.js 20 distributions setup
              curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
              apt-get install -y nodejs
              
              # 4. Install AWS CodeDeploy Agent Engine
              cd /home/ubuntu
              wget https://aws-codedeploy-us-east-1.s3.us-east-1.amazonaws.com/latest/install
              chmod +x ./install
              ./install auto
              systemctl start codedeploy-agent
              
              # 5. Clean up default web root directory
              rm -rf /var/www/html/*
              systemctl restart nginx
  EOF

  tags = {
    Name = "micro-netflix-frontend-server"
  }
}


# =================================================================
# AWS CODEDEPLOY COMPONENT SPECIFICATIONS
# =================================================================

resource "aws_codedeploy_app" "frontend_app" {
  compute_platform = "Server"
  name             = "micro-netflix-frontend-application"
}

resource "aws_codedeploy_deployment_group" "frontend_dg" {
  app_name               = aws_codedeploy_app.frontend_app.name
  deployment_group_name  = "micro-netflix-deployment-group"
  service_role_arn       = data.aws_iam_role.lab_role.arn
  deployment_config_name = "CodeDeployDefault.AllAtOnce"

  ec2_tag_set {
    ec2_tag_filter {
      key   = "Name"
      type  = "KEY_AND_VALUE"
      value = "micro-netflix-frontend-server"
    }
  }
}
