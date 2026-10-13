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

data "aws_ecr_repository" "web" {
  name = var.repository_name
}

# --- Control Plane: Kubernetes API, яким керує AWS

resource "aws_iam_role" "cluster" {
  name = "${var.name}-cluster"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_eks_cluster" "main" {
  name     = var.name
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids = data.aws_subnets.public.ids
  }

  # Хто створив кластер (роль cli-admin-role), той і його адміністратор у kubectl
  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  depends_on = [aws_iam_role_policy_attachment.cluster]
}

# --- Worker Nodes: Node Group з EC2, на яких запускаються поди

resource "aws_iam_role" "node" {
  name = "${var.name}-node"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Вузлу потрібні: підключення до кластера, мережа подів (CNI) і читання образів з ECR
resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
  ])

  role       = aws_iam_role.node.name
  policy_arn = each.value
}

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.name}-nodes"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = data.aws_subnets.public.ids
  instance_types  = [var.node_instance_type]

  scaling_config {
    desired_size = var.node_count
    min_size     = 1
    max_size     = var.node_count
  }

  depends_on = [aws_iam_role_policy_attachment.node]
}

# --- Доступ до сторінки: Service типу NodePort слухає порт node_port на кожному вузлі

resource "aws_vpc_security_group_ingress_rule" "node_port" {
  security_group_id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  description       = "Web page via Kubernetes NodePort"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = var.node_port
  to_port           = var.node_port
  ip_protocol       = "tcp"
}
