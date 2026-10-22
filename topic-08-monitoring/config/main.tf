terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# Профіль admin з гайду: CLI бере роль cli-admin-role через student-base.
provider "aws" {
  profile = var.aws_profile
  region  = var.region

  default_tags {
    tags = {
      Project   = "goit-topic-08"
      ManagedBy = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

# --- Бакет для знімків конфігурації: Config складає сюди історію змін

resource "aws_s3_bucket" "config" {
  bucket = "${var.name}-${data.aws_caller_identity.current.account_id}"

  # Дозволяє terraform destroy видалити бакет разом зі знімками
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "config" {
  bucket = aws_s3_bucket.config.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- IAM-роль Config: читати налаштування ресурсів і писати знімки в бакет

resource "aws_iam_role" "config" {
  name = "${var.name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "config.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "config" {
  role       = aws_iam_role.config.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

resource "aws_iam_role_policy" "config_bucket" {
  role = aws_iam_role.config.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.config.arn
      },
      {
        Effect   = "Allow"
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.config.arn}/AWSLogs/*"
      },
    ]
  })
}

# --- Recorder: що записувати. Config бере гроші за кожен записаний стан ресурсу,
# тому записуємо лише два типи — ті, що перевіряють правила нижче.
# Ім'я default — як у майстра в консолі: якщо Config уже вмикали, Terraform перезапише
# той recorder, а не впаде з помилкою «у регіоні може бути лише один recorder».

resource "aws_config_configuration_recorder" "main" {
  name     = "default"
  role_arn = aws_iam_role.config.arn

  recording_group {
    all_supported  = false
    resource_types = ["AWS::EC2::SecurityGroup", "AWS::S3::Bucket"]
  }
}

resource "aws_config_delivery_channel" "main" {
  name           = "default"
  s3_bucket_name = aws_s3_bucket.config.id

  depends_on = [aws_config_configuration_recorder.main, aws_iam_role_policy.config_bucket]
}

resource "aws_config_configuration_recorder_status" "main" {
  name       = aws_config_configuration_recorder.main.name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.main]
}

# --- Rules: готові правила від AWS. Config перевіряє кожен ресурс при зміні
# і фарбує його в Compliant або Noncompliant.

resource "aws_config_config_rule" "rule" {
  for_each = {
    # SSH (порт 22) не відкритий для всього інтернету (0.0.0.0/0)
    "${var.name}-restricted-ssh" = "INCOMING_SSH_DISABLED"
    # У бакета ввімкнено Block Public Access
    "${var.name}-s3-no-public-access" = "S3_BUCKET_LEVEL_PUBLIC_ACCESS_PROHIBITED"
  }

  name = each.key

  source {
    owner             = "AWS"
    source_identifier = each.value
  }

  depends_on = [aws_config_configuration_recorder_status.main]
}
