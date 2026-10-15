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

variable "my_ip_cidr" {
  description = "Ваш публічний IP у форматі x.x.x.x/32 — лише з нього можна підключитися до бази"
  type        = string
}

variable "name" {
  description = "Ім'я бази RDS, її SG і subnet group"
  type        = string
  default     = "goit-rds"
}

variable "instance_class" {
  description = "Клас інстансу RDS"
  type        = string
  default     = "db.t4g.micro"
}
