output "bucket_name" {
  value = aws_s3_bucket.orders.id
}

output "function_name" {
  value = aws_lambda_function.orders.function_name
}

output "log_group" {
  value = aws_cloudwatch_log_group.lambda.name
}

output "failed_queue_url" {
  value = aws_sqs_queue.failed.url
}
