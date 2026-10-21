output "bucket_name" {
  value = aws_s3_bucket.site.id
}

# Пряма адреса об'єкта в S3. Бакет приватний, тож тут буде 403 AccessDenied.
output "object_url" {
  value = "https://${aws_s3_bucket.site.bucket_regional_domain_name}/index.html"
}
