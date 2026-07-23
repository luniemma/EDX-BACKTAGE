output "backstage_url" {
  description = "Browse here once the ingress port-forward is running."
  value       = "https://${var.backstage_host}:${var.ingress_local_port}"
}

output "argocd_url" {
  description = "Browse here once the ingress port-forward is running."
  value       = "https://${var.argocd_host}:${var.ingress_local_port}"
}

output "port_forward_command" {
  description = "Run this and leave it open — it is what makes the URLs above reachable."
  value       = "kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller ${var.ingress_local_port}:443"
}

output "ca_export_command" {
  description = "Export the local root CA, then import it to remove the browser trust warning (see README)."
  value       = "kubectl get secret local-ca-root -n cert-manager -o jsonpath='{.data.tls\\.crt}' | base64 -d > local-ca.crt"
}
