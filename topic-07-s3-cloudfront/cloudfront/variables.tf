variable "aws_profile" {
  description = "Профіль AWS CLI (з гайду: admin бере роль cli-admin-role)"
  type        = string
  default     = "admin"
}

variable "region" {
  description = "Регіон AWS (CloudFront глобальний, регіон потрібен, щоб знайти бакет)"
  type        = string
  default     = "eu-central-1"
}

variable "name" {
  description = "Префікс імені бакета з ../s3 — має збігатися з тамтешньою змінною name"
  type        = string
  default     = "goit-site"
}
