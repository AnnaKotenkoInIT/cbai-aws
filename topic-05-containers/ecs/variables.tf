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
  description = "Значення змінної name з теми 3 — за ним шукаємо VPC, підмережі та SG"
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
  description = "Ім'я кластера, сервісу та task definition"
  type        = string
  default     = "goit-ecs"
}

variable "desired_count" {
  description = "Скільки задач (контейнерів) тримати запущеними"
  type        = number
  default     = 1
}
