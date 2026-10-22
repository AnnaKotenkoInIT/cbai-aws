output "trail_arn" {
  value = aws_cloudtrail.main.arn
}

output "bucket_name" {
  value = aws_s3_bucket.trail.id
}

output "log_group" {
  value = aws_cloudwatch_log_group.trail.name
}
