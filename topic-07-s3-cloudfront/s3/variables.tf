variable "aws_profile" {
  description = "Профіль AWS CLI (з гайду: admin бере роль cli-admin-role)"
  type        = string
  default     = "admin"
}

variable "region" {
  description = "Регіон AWS"
  type        = string
  default     = "eu-central-1"
}

variable "name" {
  description = "Префікс імені бакета (до нього додається номер акаунта)"
  type        = string
  default     = "goit-site"
}
