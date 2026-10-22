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

locals {
  account_id = data.aws_caller_identity.current.account_id
  # ARN trail-а збираємо вручну: він потрібен у політиці бакета ще до створення trail-а
  trail_arn = "arn:aws:cloudtrail:${var.region}:${local.account_id}:trail/${var.name}"
}

# --- Store: S3-бакет для журналу. Тут записи зберігаються стільки, скільки треба,
# а не 90 днів, як у Event history.

resource "aws_s3_bucket" "trail" {
  bucket = "${var.name}-${local.account_id}"

  # Дозволяє terraform destroy видалити бакет разом з журналами
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "trail" {
  bucket = aws_s3_bucket.trail.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Писати в бакет може лише сервіс CloudTrail і лише для нашого trail-а
resource "aws_s3_bucket_policy" "trail" {
  bucket = aws_s3_bucket.trail.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.trail.arn
        Condition = { StringEquals = { "aws:SourceArn" = local.trail_arn } }
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.trail.arn}/AWSLogs/${local.account_id}/*"
        Condition = {
          StringEquals = {
            "aws:SourceArn" = local.trail_arn
            "s3:x-amz-acl"  = "bucket-owner-full-control"
          }
        }
      },
    ]
  })
}

# --- Store: копія журналу в CloudWatch Logs, щоб шукати по ньому й будувати алярми

resource "aws_cloudwatch_log_group" "trail" {
  name              = "/${var.name}/events"
  retention_in_days = 7
}

resource "aws_iam_role" "trail_logs" {
  name = "${var.name}-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudtrail.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "trail_logs" {
  role = aws_iam_role.trail_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.trail.arn}:*"
    }]
  })
}

# --- Capture: trail записує management events (хто, коли і що змінив) з усіх регіонів.
# Перша копія management events в акаунті безкоштовна.

resource "aws_cloudtrail" "main" {
  name                       = var.name
  s3_bucket_name             = aws_s3_bucket.trail.id
  is_multi_region_trail      = true
  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.trail.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.trail_logs.arn

  # Щогодини CloudTrail підписує дайджест журналів: підробку записів заднім числом буде видно
  enable_log_file_validation = true

  depends_on = [aws_s3_bucket_policy.trail, aws_iam_role_policy.trail_logs]
}

# --- Act: будь-яка зміна security group → метрика → алярм → лист

resource "aws_cloudwatch_log_metric_filter" "sg_changes" {
  name           = "${var.name}-sg-changes"
  log_group_name = aws_cloudwatch_log_group.trail.name

  pattern = "{ ($.eventName = CreateSecurityGroup) || ($.eventName = DeleteSecurityGroup) || ($.eventName = AuthorizeSecurityGroupIngress) || ($.eventName = RevokeSecurityGroupIngress) || ($.eventName = AuthorizeSecurityGroupEgress) || ($.eventName = RevokeSecurityGroupEgress) }"

  metric_transformation {
    name      = "SecurityGroupChanges"
    namespace = "GoIT/CloudTrail"
    value     = "1"
  }
}

resource "aws_sns_topic" "alerts" {
  name = "${var.name}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  count = var.alert_email == "" ? 0 : 1

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "sg_changes" {
  alarm_name          = "${var.name}-sg-changes"
  alarm_description   = "Хтось змінив security group: шукайте, хто саме, у CloudTrail"
  namespace           = "GoIT/CloudTrail"
  metric_name         = "SecurityGroupChanges"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

# --- Review: збережений запит Logs Insights «хто й що робив із security groups»

resource "aws_cloudwatch_query_definition" "sg_changes" {
  name            = "${var.name}/who-changed-security-groups"
  log_group_names = [aws_cloudwatch_log_group.trail.name]

  query_string = <<-EOT
    fields eventTime, eventName, userIdentity.arn, sourceIPAddress, requestParameters.groupId
    | filter eventSource = "ec2.amazonaws.com" and eventName like /SecurityGroup/
    | sort eventTime desc
  EOT
}
