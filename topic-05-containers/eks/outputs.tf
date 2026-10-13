output "cluster_name" {
  value = aws_eks_cluster.main.name
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --profile ${var.aws_profile} --region ${var.region} --name ${aws_eks_cluster.main.name}"
}

# Готовий маніфест з образом з ECR: terraform output -raw k8s_manifest | kubectl apply -f -
output "k8s_manifest" {
  value = templatefile("${path.module}/app.yaml.tftpl", {
    image     = "${data.aws_ecr_repository.web.repository_url}:${var.image_tag}"
    node_port = var.node_port
  })
}
