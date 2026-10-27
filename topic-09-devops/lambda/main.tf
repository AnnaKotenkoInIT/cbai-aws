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

# --- Бакет: сюди завантажують CSV із замовленнями (incoming/), а Lambda кладе звіти (reports/)

resource "aws_s3_bucket" "orders" {
  bucket = "${var.name}-${data.aws_caller_identity.current.account_id}"

  # Дозволяє terraform destroy видалити бакет разом з файлами
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "orders" {
  bucket = aws_s3_bucket.orders.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- Черга для подій, які функція не змогла обробити (DLQ)

resource "aws_sqs_queue" "failed" {
  name                      = "${var.name}-failed"
  message_retention_seconds = 86400
}

# --- IAM-роль функції: читати incoming/, писати reports/, слати в чергу, писати логи

resource "aws_iam_role" "lambda" {
  name = "${var.name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "logs" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda" {
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.orders.arn}/incoming/*"
      },
      {
        Effect   = "Allow"
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.orders.arn}/reports/*"
      },
      {
        Effect   = "Allow"
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.failed.arn
      },
    ]
  })
}

# --- Функція: код з src/ Terraform пакує в zip і завантажує в Lambda

data "archive_file" "src" {
  type        = "zip"
  source_dir  = "${path.module}/src"
  output_path = "${path.module}/lambda.zip"
}

# Логи функції: Lambda пише в групу /aws/lambda/<ім'я>. Створюємо її самі, щоб задати retention.
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.name}"
  retention_in_days = 7
}

resource "aws_lambda_function" "orders" {
  function_name    = var.name
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.13"
  handler          = "handler.handler"
  filename         = data.archive_file.src.output_path
  source_code_hash = data.archive_file.src.output_base64sha256
  memory_size      = 128
  timeout          = 10

  depends_on = [aws_cloudwatch_log_group.lambda, aws_iam_role_policy_attachment.logs]
}

# Асинхронний виклик (як від S3): без повторних спроб, невдалу подію одразу шлемо в чергу
resource "aws_lambda_function_event_invoke_config" "orders" {
  function_name          = aws_lambda_function.orders.function_name
  maximum_retry_attempts = 0

  destination_config {
    on_failure {
      destination = aws_sqs_queue.failed.arn
    }
  }

  depends_on = [aws_iam_role_policy.lambda]
}

# --- Тригер: S3 викликає функцію на кожен новий .csv у incoming/

resource "aws_lambda_permission" "s3" {
  statement_id   = "AllowS3Invoke"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.orders.function_name
  principal      = "s3.amazonaws.com"
  source_arn     = aws_s3_bucket.orders.arn
  source_account = data.aws_caller_identity.current.account_id
}

# Звіти пишемо в reports/, а не в incoming/: інакше функція викликала б сама себе без кінця
resource "aws_s3_bucket_notification" "orders" {
  bucket = aws_s3_bucket.orders.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.orders.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "incoming/"
    filter_suffix       = ".csv"
  }

  depends_on = [aws_lambda_permission.s3]
}
