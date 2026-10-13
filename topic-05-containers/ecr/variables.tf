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

variable "repository_name" {
  description = "Ім'я ECR-репозиторію (ECS і EKS шукають його за цим іменем)"
  type        = string
  default     = "goit-web"
}
