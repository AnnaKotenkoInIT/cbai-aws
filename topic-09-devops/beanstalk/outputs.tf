output "url" {
  value = "http://${aws_elastic_beanstalk_environment.app.cname}"
}

output "application_name" {
  value = aws_elastic_beanstalk_application.app.name
}

output "environment_name" {
  value = aws_elastic_beanstalk_environment.app.name
}

output "bucket_name" {
  value = aws_s3_bucket.versions.id
}
