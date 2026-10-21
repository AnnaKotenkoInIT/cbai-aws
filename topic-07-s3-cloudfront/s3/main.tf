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
      Project   = "goit-topic-07"
      ManagedBy = "terraform"
    }
  }
}

# --- Amazon S3: бакет для статики фронтенду. VPC не потрібна — S3 працює на рівні регіону.
# Ім'я бакета унікальне в усьому світі, тому додаємо номер акаунта.

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "site" {
  bucket = "${var.name}-${data.aws_caller_identity.current.account_id}"

  # Дозволяє terraform destroy видалити бакет разом з файлами
  force_destroy = true
}

# Бакет повністю приватний: жодного публічного доступу. Відкривати сайт буде CloudFront (папка ../cloudfront).
resource "aws_s3_bucket_public_access_block" "site" {
  bucket = aws_s3_bucket.site.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- Об'єкти: кожен файл з site/ стає об'єктом, шлях до файлу — його ключем (assets/app.js).
# Content-Type обов'язковий: без нього браузер не покаже сторінку, а запропонує її завантажити.

locals {
  content_types = {
    html = "text/html; charset=utf-8"
    css  = "text/css; charset=utf-8"
    js   = "text/javascript; charset=utf-8"
    svg  = "image/svg+xml"
    png  = "image/png"
  }
}

resource "aws_s3_object" "site" {
  for_each = fileset("${path.module}/site", "**")

  bucket       = aws_s3_bucket.site.id
  key          = each.value
  source       = "${path.module}/site/${each.value}"
  source_hash  = filemd5("${path.module}/site/${each.value}")
  content_type = local.content_types[regex("[^.]+$", each.value)]
}
