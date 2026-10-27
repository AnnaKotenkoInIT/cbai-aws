terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

# Профіль admin з гайду: CLI бере роль cli-admin-role через student-base.
provider "aws" {
  profile = var.aws_profile
  region  = var.region

  default_tags {
    tags = {
      Project   = "goit-topic-09"
      ManagedBy = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

# --- Мережа з теми 3: не створюємо, а знаходимо за тегами (спершу застосуйте topic-03-vpc)

data "aws_vpc" "main" {
  tags = {
    Project = "goit-topic-03"
    Name    = var.vpc_name
  }
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }

  filter {
    name   = "tag:Name"
    values = ["${var.vpc_name}-public-*"]
  }
}

# Найновіша платформа «Python 3.13 на Amazon Linux 2023»
data "aws_elastic_beanstalk_solution_stack" "python" {
  most_recent = true
  name_regex  = "^64bit Amazon Linux 2023 (.*) running Python 3\\.13$"
}

# --- Бакет для версій застосунку: кожна версія — zip з кодом

resource "aws_s3_bucket" "versions" {
  bucket = "${var.name}-versions-${data.aws_caller_identity.current.account_id}"

  # Дозволяє terraform destroy видалити бакет разом з версіями
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "versions" {
  bucket = aws_s3_bucket.versions.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "archive_file" "app" {
  type        = "zip"
  source_dir  = "${path.module}/app"
  output_path = "${path.module}/app.zip"
}

resource "aws_s3_object" "app" {
  bucket = aws_s3_bucket.versions.id
  key    = "versions/app-${data.archive_file.app.output_md5}.zip"
  source = data.archive_file.app.output_path
}

# --- IAM: сервісна роль (Beanstalk стежить за здоров'ям) і роль серверів

resource "aws_iam_role" "service" {
  name = "${var.name}-service-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "elasticbeanstalk.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "service" {
  role       = aws_iam_role.service.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSElasticBeanstalkEnhancedHealth"
}

resource "aws_iam_role" "ec2" {
  name = "${var.name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Готова політика для вебсерверів Beanstalk: логи в CloudWatch, звіти про здоров'я
resource "aws_iam_role_policy_attachment" "ec2" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkWebTier"
}

# Сервери завантажують zip з кодом з нашого бакета
resource "aws_iam_role_policy" "ec2_versions" {
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "s3:GetObject"
      Resource = "${aws_s3_bucket.versions.arn}/*"
    }]
  })
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.name}-ec2-profile"
  role = aws_iam_role.ec2.name
}

# --- Застосунок → версія → середовище

resource "aws_elastic_beanstalk_application" "app" {
  name        = var.name
  description = "GoIT, тема 9: Flask на Elastic Beanstalk"
}

resource "aws_elastic_beanstalk_application_version" "app" {
  name        = "tf-${substr(data.archive_file.app.output_md5, 0, 8)}"
  application = aws_elastic_beanstalk_application.app.name
  bucket      = aws_s3_bucket.versions.id
  key         = aws_s3_object.app.key
}

locals {
  # [namespace, параметр, значення] — те саме, що вкладка Configuration у консолі Beanstalk
  settings = [
    # Мережа: VPC і публічні підмережі з теми 3
    ["aws:ec2:vpc", "VPCId", data.aws_vpc.main.id],
    ["aws:ec2:vpc", "Subnets", join(",", sort(data.aws_subnets.public.ids))],
    ["aws:ec2:vpc", "ELBSubnets", join(",", sort(data.aws_subnets.public.ids))],
    ["aws:ec2:vpc", "AssociatePublicIpAddress", "true"],

    # Балансувальник (ALB) перед групою Auto Scaling
    ["aws:elasticbeanstalk:environment", "EnvironmentType", "LoadBalanced"],
    ["aws:elasticbeanstalk:environment", "LoadBalancerType", "application"],
    ["aws:elasticbeanstalk:environment", "ServiceRole", aws_iam_role.service.arn],
    ["aws:autoscaling:asg", "MinSize", tostring(var.min_size)],
    ["aws:autoscaling:asg", "MaxSize", tostring(var.max_size)],
    ["aws:ec2:instances", "InstanceTypes", var.instance_type],
    ["aws:autoscaling:launchconfiguration", "IamInstanceProfile", aws_iam_instance_profile.ec2.name],
    ["aws:autoscaling:launchconfiguration", "DisableIMDSv1", "true"],

    # Здоров'я і логи: розширений моніторинг і логи в CloudWatch на 7 днів
    ["aws:elasticbeanstalk:healthreporting:system", "SystemType", "enhanced"],
    ["aws:elasticbeanstalk:cloudwatch:logs", "StreamLogs", "true"],
    ["aws:elasticbeanstalk:cloudwatch:logs", "RetentionInDays", "7"],
    ["aws:elasticbeanstalk:cloudwatch:logs", "DeleteOnTerminate", "true"],
  ]
}

resource "aws_elastic_beanstalk_environment" "app" {
  name                = "${var.name}-env"
  application         = aws_elastic_beanstalk_application.app.name
  solution_stack_name = data.aws_elastic_beanstalk_solution_stack.python.name
  version_label       = aws_elastic_beanstalk_application_version.app.name

  dynamic "setting" {
    for_each = local.settings

    content {
      namespace = setting.value[0]
      name      = setting.value[1]
      value     = setting.value[2]
    }
  }

  # Terraform розгортає лише першу версію. Далі версії викочують через AWS CLI (крок 3 у README),
  # як це робив би CI/CD, тож Terraform не повертає середовище до своєї версії.
  lifecycle {
    ignore_changes = [version_label]
  }

  depends_on = [aws_iam_role_policy_attachment.service, aws_iam_role_policy_attachment.ec2, aws_iam_role_policy.ec2_versions]
}
