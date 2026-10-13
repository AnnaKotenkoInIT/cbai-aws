output "cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "service_name" {
  value = aws_ecs_service.web.name
}

output "image" {
  value = "${data.aws_ecr_repository.web.repository_url}:${var.image_tag}"
}
