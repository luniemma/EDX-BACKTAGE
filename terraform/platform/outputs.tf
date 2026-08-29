output "cluster_name" {
  description = "EKS cluster name. `aws eks update-kubeconfig --name <this>` to get a kubeconfig."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 CA bundle for the API server."
  value       = module.eks.cluster_certificate_authority_data
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer, for IRSA roles created by other roots."
  value       = module.eks.cluster_oidc_issuer_url
}

output "oidc_provider_arn" {
  description = "IAM OIDC provider ARN for this cluster."
  value       = module.eks.oidc_provider_arn
}

output "vpc_id" {
  description = "Platform VPC."
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Subnets the nodes and load balancers live in."
  value       = module.vpc.public_subnets
}

output "region" {
  description = "Region, so downstream roots do not have to be told twice."
  value       = var.aws_region
}

output "kubeconfig_command" {
  description = "Copy-paste to point kubectl at this cluster."
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}
