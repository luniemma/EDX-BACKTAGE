output "endpoint" {
  description = "Hostname only. This is the value values-lean.yaml needs — RHDH supplies the port separately."
  value       = aws_db_instance.this.address
}

output "port" {
  description = "PostgreSQL port."
  value       = aws_db_instance.this.port
}

output "database" {
  description = "Initial database name."
  value       = aws_db_instance.this.db_name
}

output "username" {
  description = "Master user. values-lean.yaml must name the same one."
  value       = aws_db_instance.this.username
}

output "master_password_secret_arn" {
  description = <<-EOT
    Secrets Manager ARN holding the AWS-managed master password. The password
    itself is deliberately not a Terraform output — it is not in state, which
    is the point of manage_master_user_password.
  EOT
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}

output "kubernetes_secret_command" {
  description = <<-EOT
    Copies the master password out of Secrets Manager into the Secret RHDH
    reads. Run it after every password rotation — nothing syncs these two
    automatically without External Secrets Operator.
  EOT
  value = join(" ", [
    "aws secretsmanager get-secret-value --secret-id",
    aws_db_instance.this.master_user_secret[0].secret_arn,
    "--region ${local.region} --query SecretString --output text",
    "| python -c \"import sys,json;print(json.load(sys.stdin)['password'])\"",
    "| xargs -I{} kubectl -n rhdh-lean create secret generic rhdh-db",
    "--from-literal=postgres-password={}",
    "--dry-run=client -o yaml | kubectl apply -f -",
  ])
}
