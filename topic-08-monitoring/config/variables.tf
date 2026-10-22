variable "aws_profile" {
  description = "Профіль AWS CLI (з гайду: admin бере роль cli-admin-role)"
  type        = string
  default     = "admin"
}

variable "region" {
  description = "Регіон AWS: Config працює окремо в кожному регіоні"
  type        = string
  default     = "eu-central-1"
}

variable "name" {
  description = "Префікс імен ресурсів"
  type        = string
  default     = "goit-config"
}
