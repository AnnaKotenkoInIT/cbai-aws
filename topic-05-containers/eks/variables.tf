variable "aws_profile" {
  description = "Профіль AWS CLI (з гайду: admin бере роль cli-admin-role)"
  type        = string
  default     = "admin"
}

variable "region" {
  description = "Регіон AWS (той самий, що й у темі 3)"
  type        = string
  default     = "eu-central-1"
}

variable "vpc_name" {
  description = "Значення змінної name з теми 3 — за ним шукаємо VPC і підмережі"
  type        = string
  default     = "goit-vpc"
}

variable "repository_name" {
  description = "Ім'я ECR-репозиторію з ../ecr"
  type        = string
  default     = "goit-web"
}

variable "image_tag" {
  description = "Тег образу в ECR"
  type        = string
  default     = "v1"
}

variable "name" {
  description = "Ім'я EKS-кластера"
  type        = string
  default     = "goit-eks"
}

variable "node_instance_type" {
  description = "Тип EC2 для вузлів"
  type        = string
  default     = "t3.small"
}

variable "node_count" {
  description = "Кількість вузлів у Node Group"
  type        = number
  default     = 1
}

variable "node_port" {
  description = "NodePort, на якому сторінка доступна з інтернету (діапазон 30000–32767)"
  type        = number
  default     = 30080
}
