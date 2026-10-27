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

variable "name" {
  description = "Ім'я застосунку Beanstalk і префікс імен ресурсів"
  type        = string
  default     = "goit-app"
}

variable "instance_type" {
  description = "Тип серверів у середовищі"
  type        = string
  default     = "t3.micro"
}

variable "min_size" {
  description = "Мінімум серверів у групі Auto Scaling"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Максимум серверів у групі Auto Scaling"
  type        = number
  default     = 2
}
