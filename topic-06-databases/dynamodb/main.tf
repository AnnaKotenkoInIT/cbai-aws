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
      Project   = "goit-topic-06"
      ManagedBy = "terraform"
    }
  }
}

# --- Amazon DynamoDB: кошики покупок. VPC не потрібна — DynamoDB працює на рівні регіону.
# Ключ складається з двох частин: клієнт (partition key) + товар (sort key).
# Решту атрибутів не описуємо: у кожного елемента вони можуть бути свої.

resource "aws_dynamodb_table" "carts" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "customer_id"
  range_key    = "product_id"

  attribute {
    name = "customer_id"
    type = "N"
  }

  attribute {
    name = "product_id"
    type = "N"
  }
}

# --- Наповнення: кожен запис із seed.json стає елементом таблиці

resource "aws_dynamodb_table_item" "seed" {
  for_each = {
    for item in jsondecode(file("${path.module}/seed.json")) :
    "${item.customer_id.N}-${item.product_id.N}" => item
  }

  table_name = aws_dynamodb_table.carts.name
  hash_key   = aws_dynamodb_table.carts.hash_key
  range_key  = aws_dynamodb_table.carts.range_key
  item       = jsonencode(each.value)
}
