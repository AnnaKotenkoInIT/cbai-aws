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

# --- Мережа з теми 3 та образ з ../ecr: не створюємо, а знаходимо

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

# SG з теми 3: HTTP зі світу — сторінка задачі відкривається напряму за її public IP
data "aws_security_group" "web" {
  vpc_id = data.aws_vpc.main.id
  name   = "${var.vpc_name}-web"
}

data "aws_ecr_repository" "web" {
  name = var.repository_name
}

# --- Кластер ECS: логічна група, де запускаються задачі (на Fargate — без власних серверів)

resource "aws_ecs_cluster" "main" {
  name = var.name
}

# --- Task execution role: дозволяє ECS завантажити образ з ECR

resource "aws_iam_role" "execution" {
  name = "${var.name}-task-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# --- Task Definition: який контейнер запускати і скільки ресурсів йому дати

resource "aws_ecs_task_definition" "web" {
  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.execution.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name         = "web"
    image        = "${data.aws_ecr_repository.web.repository_url}:${var.image_tag}"
    essential    = true
    portMappings = [{ containerPort = 80 }]
  }])
}

# --- Service: тримає потрібну кількість задач запущеними

resource "aws_ecs_service" "web" {
  name            = var.name
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.web.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  # Публічні підмережі теми 3 + public IP: образ тягнеться з ECR через Internet Gateway, NAT не потрібен
  network_configuration {
    subnets          = data.aws_subnets.public.ids
    security_groups  = [data.aws_security_group.web.id]
    assign_public_ip = true
  }
}
