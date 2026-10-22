variable "aws_profile" {
  description = "Профіль AWS CLI (з гайду: admin бере роль cli-admin-role)"
  type        = string
  default     = "admin"
}

variable "region" {
  description = "Регіон AWS: тут живуть trail, бакет журналу й алярм"
  type        = string
  default     = "eu-central-1"
}

variable "name" {
  description = "Ім'я trail-а і префікс решти ресурсів"
  type        = string
  default     = "goit-trail"
}

variable "alert_email" {
  description = "Email для листів алярму. Порожньо — алярм спрацює, але лист не прийде"
  type        = string
  default     = ""
}
