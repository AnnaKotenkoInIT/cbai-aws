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
      Project   = "goit-topic-05"
      ManagedBy = "terraform"
    }
  }
}

# --- Amazon ECR: приватний репозиторій для образу з app/, спільного для ECS і EKS

resource "aws_ecr_repository" "web" {
  name                 = var.repository_name
  image_tag_mutability = "MUTABLE"

  # Дозволяє terraform destroy видалити репозиторій разом із завантаженими образами
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }
}
