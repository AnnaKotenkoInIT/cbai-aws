output "web_url" {
  value = "http://${aws_instance.web.public_ip}"
}

output "instance_id" {
  value = aws_instance.web.id
}

output "log_group" {
  value = aws_cloudwatch_log_group.access.name
}

output "dashboard_url" {
  value = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards/dashboard/${aws_cloudwatch_dashboard.main.dashboard_name}"
}
