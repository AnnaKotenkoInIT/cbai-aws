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

variable "name" {
  description = "Префікс імен ресурсів цієї практики"
  type        = string
  default     = "goit-monitor"
}

variable "instance_type" {
  description = "Тип EC2-інстансу"
  type        = string
  default     = "t3.micro"
}

variable "cpu_threshold" {
  description = "Поріг алярму CPU, %"
  type        = number
  default     = 70
}

variable "alert_email" {
  description = "Email для листів алярму. Порожньо — алярм спрацює, але лист не прийде"
  type        = string
  default     = ""
}
