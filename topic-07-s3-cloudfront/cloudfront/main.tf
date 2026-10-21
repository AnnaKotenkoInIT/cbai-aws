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

# --- Бакет з ../s3: не створюємо, а знаходимо за тим самим ім'ям

data "aws_caller_identity" "current" {}

data "aws_s3_bucket" "site" {
  bucket = "${var.name}-${data.aws_caller_identity.current.account_id}"
}

# --- Origin Access Control: CloudFront підписує кожен запит до S3, і бакет пускає лише його

resource "aws_cloudfront_origin_access_control" "site" {
  name                              = var.name
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Готова політика кешування від AWS: файли живуть у кеші edge-серверів до 24 годин, стиснення gzip/brotli
data "aws_cloudfront_cache_policy" "optimized" {
  name = "Managed-CachingOptimized"
}

# --- Amazon CloudFront: CDN перед приватним бакетом

resource "aws_cloudfront_distribution" "site" {
  enabled             = true
  comment             = var.name
  default_root_object = "index.html"

  # Лише edge-сервери Європи та Північної Америки: найдешевший клас
  price_class = "PriceClass_100"

  origin {
    origin_id                = "s3"
    domain_name              = data.aws_s3_bucket.site.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  default_cache_behavior {
    target_origin_id       = "s3"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = data.aws_cloudfront_cache_policy.optimized.id
    compress               = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # HTTPS з безкоштовним сертифікатом *.cloudfront.net
  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# --- Політика бакета: читати файли може лише сервіс CloudFront і лише для цієї дистрибуції.
# Пряме звернення до S3 так і лишається 403 AccessDenied.

resource "aws_s3_bucket_policy" "site" {
  bucket = data.aws_s3_bucket.site.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${data.aws_s3_bucket.site.arn}/*"
      Condition = {
        StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.site.arn }
      }
    }]
  })
}
