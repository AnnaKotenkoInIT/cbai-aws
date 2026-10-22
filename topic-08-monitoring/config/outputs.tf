output "rules" {
  value = keys(aws_config_config_rule.rule)
}

output "bucket_name" {
  value = aws_s3_bucket.config.id
}
