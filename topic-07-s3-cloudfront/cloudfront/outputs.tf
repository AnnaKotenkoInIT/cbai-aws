output "site_url" {
  value = "https://${aws_cloudfront_distribution.site.domain_name}"
}

# Потрібен для інвалідації кешу: aws cloudfront create-invalidation --distribution-id ...
output "distribution_id" {
  value = aws_cloudfront_distribution.site.id
}
