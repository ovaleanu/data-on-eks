output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = "aws eks --region ${local.region} update-kubeconfig --name ${module.eks.cluster_name}"
}

output "eks_api_server_url" {
  description = "Your eks API server endpoint"
  value       = module.eks.cluster_endpoint
}

output "grafana_secret_name" {
  description = "Grafana password secret name"
  value       = aws_secretsmanager_secret.grafana.name
}
