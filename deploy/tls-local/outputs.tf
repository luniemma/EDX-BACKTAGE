output "backstage_url" {
  description = "HTTPS URL for Backstage (needs the hosts-file entry and minikube tunnel)."
  value       = "https://${var.backstage_host}"
}

output "argocd_url" {
  description = "HTTPS URL for the ArgoCD UI."
  value       = "https://${var.argocd_host}"
}

output "ca_export_command" {
  description = "Run this to export the local root CA, then import it into your OS/browser trust store to make the certs trusted."
  value       = "kubectl get secret local-ca-root -n cert-manager -o jsonpath='{.data.tls\\.crt}' | base64 -d > local-ca.crt"
}

output "hosts_file_entries" {
  description = "Add these to the Windows hosts file (C:\\Windows\\System32\\drivers\\etc\\hosts) as Administrator, then run `minikube tunnel`."
  value       = "127.0.0.1 ${var.backstage_host}\n127.0.0.1 ${var.argocd_host}"
}
