output "endpoint" {
  value = aws_db_instance.main.address
}

output "db_password" {
  value     = random_password.db.result
  sensitive = true
}
