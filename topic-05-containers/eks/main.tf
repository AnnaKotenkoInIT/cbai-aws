terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    helm = {
      source  = "hashicorp/helm"
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

# --- Доступ до Kubernetes у Management Console: root-користувач акаунта стає адміністратором кластера.
# Без цього вкладка Resources у консолі EKS пише «doesn't have access to Kubernetes objects».

data "aws_caller_identity" "current" {}

resource "aws_eks_access_entry" "console" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
}

resource "aws_eks_access_policy_association" "console" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_eks_access_entry.console.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
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

# --- Ingress: AWS Load Balancer Controller створює ALB для кожного об'єкта Ingress.
# Сам контролер безкоштовний (один под), ALB з'являється лише після kubectl apply Ingress.

# Pod Identity: под контролера отримує IAM-роль без ключів доступу
resource "aws_eks_addon" "pod_identity" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "eks-pod-identity-agent"

  depends_on = [aws_eks_node_group.main]
}

resource "aws_iam_role" "lb_controller" {
  name = "${var.name}-lb-controller"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

# Офіційна політика контролера v3.5.0 (docs/install/iam_policy.json): керування ALB, target groups і SG
resource "aws_iam_role_policy" "lb_controller" {
  role   = aws_iam_role.lb_controller.id
  policy = file("${path.module}/lb-controller-policy.json")
}

resource "aws_eks_pod_identity_association" "lb_controller" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.lb_controller.arn
}

# Helm ставить контролер у кластер від імені того ж профілю AWS, що й kubectl
provider "helm" {
  kubernetes = {
    host                   = aws_eks_cluster.main.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.main.certificate_authority[0].data)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.main.name, "--profile", var.aws_profile, "--region", var.region]
    }
  }

  # Власні налаштування репозиторіїв Helm, щоб не залежати від локальних `helm repo add`
  repository_config_path = "${path.module}/.terraform/helm/repositories.yaml"
  repository_cache       = "${path.module}/.terraform/helm/cache"
}

resource "helm_release" "lb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "3.5.0"
  namespace  = "kube-system"

  # region і vpcId задаємо явно, щоб контролер не питав їх у метаданих EC2
  values = [yamlencode({
    clusterName  = aws_eks_cluster.main.name
    region       = var.region
    vpcId        = data.aws_vpc.main.id
    replicaCount = 1
  })]

  depends_on = [aws_eks_addon.pod_identity, aws_eks_pod_identity_association.lb_controller, aws_iam_role_policy.lb_controller]
}

# ALB створює контролер, а не Terraform. Тому під час destroy, поки контролер ще працює,
# видаляємо всі Ingress — і контролер прибирає свої ALB. Інакше ALB лишився б і заважав видалити VPC.
resource "terraform_data" "delete_ingresses" {
  input = {
    cluster = aws_eks_cluster.main.name
    profile = var.aws_profile
    region  = var.region
  }

  provisioner "local-exec" {
    when        = destroy
    working_dir = path.module
    command     = "aws eks update-kubeconfig --name ${self.input.cluster} --profile ${self.input.profile} --region ${self.input.region} --kubeconfig .terraform/kubeconfig && kubectl --kubeconfig .terraform/kubeconfig delete ingress --all --all-namespaces --wait"
  }

  depends_on = [helm_release.lb_controller]
}
