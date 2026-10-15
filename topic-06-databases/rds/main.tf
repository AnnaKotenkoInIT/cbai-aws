terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
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

# --- Мережа з теми 3: не створюємо, а знаходимо

data "aws_vpc" "main" {
  tags = {
    Project = "goit-topic-03"
    Name    = var.vpc_name
  }
}

# Публічні підмережі, щоб до бази можна було підключитися з вашого комп'ютера.
# У продакшені базу кладуть у приватні підмережі, а застосунок ходить до неї зсередини VPC.
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

# --- Доступ: PostgreSQL (порт 5432) лише з вашого IP

resource "aws_security_group" "db" {
  name        = "${var.name}-db"
  description = "PostgreSQL from my IP only"
  vpc_id      = data.aws_vpc.main.id

  ingress {
    description = "PostgreSQL from my IP"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }
}

# Підмережі у двох AZ, з яких RDS вибирає місце для бази
resource "aws_db_subnet_group" "main" {
  name       = var.name
  subnet_ids = data.aws_subnets.public.ids
}

# --- Пароль адміністратора бази: генерується і лежить лише в локальному terraform.tfstate

resource "random_password" "db" {
  length  = 20
  special = false
}

# --- Amazon RDS: керований PostgreSQL

resource "aws_db_instance" "main" {
  identifier        = var.name
  engine            = "postgres"
  engine_version    = "18"
  instance_class    = var.instance_class
  allocated_storage = 20

  db_name  = "shop"
  username = "goit"
  password = random_password.db.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = true

  # Навчальна база: без фінального снапшота, щоб terraform destroy нічого не лишав
  skip_final_snapshot = true
}

# --- Наповнення: seed.sql виконує psql у Docker-контейнері на вашому комп'ютері.
# Повторно запускається, лише якщо змінився seed.sql або базу створено заново.

resource "terraform_data" "seed" {
  triggers_replace = [aws_db_instance.main.id, filesha256("${path.module}/seed.sql")]

  provisioner "local-exec" {
    working_dir = path.module
    command     = "docker run --rm -i -e PGPASSWORD postgres:18-alpine psql -h ${aws_db_instance.main.address} -U ${aws_db_instance.main.username} -d ${aws_db_instance.main.db_name} -q -v ON_ERROR_STOP=1 < seed.sql"
    # nonsensitive: інакше Terraform сховає весь вивід psql разом з помилками. Пароль у вивід не потрапляє.
    environment = { PGPASSWORD = nonsensitive(random_password.db.result) }
  }
}
