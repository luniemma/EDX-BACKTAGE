output "repository_url" {
  description = "Fully-qualified ECR repository URL (use as image.repository in Helm values)"
  value       = aws_ecr_repository.this.repository_url
}

output "repository_arn" {
  description = "ECR repository ARN"
  value       = aws_ecr_repository.this.arn
}

output "registry_id" {
  description = "AWS account ID that owns the registry"
  value       = aws_ecr_repository.this.registry_id
}

output "github_push_role_arn" {
  description = "IAM role ARN for GitHub Actions to assume via OIDC when pushing images"
  value       = aws_iam_role.github_push.arn
}

output "pull_policy_arn" {
  description = "IAM policy ARN granting pull access. Attach to your EKS node role or an IRSA role."
  value       = aws_iam_policy.pull.arn
}

output "terraform_plan_role_arn" {
  description = "Read-only role assumed by the terraform plan workflow on PRs"
  value       = aws_iam_role.tf_plan.arn
}

output "terraform_apply_role_arn" {
  description = "Read/write role assumed by the terraform apply workflow on main"
  value       = aws_iam_role.tf_apply.arn
}
