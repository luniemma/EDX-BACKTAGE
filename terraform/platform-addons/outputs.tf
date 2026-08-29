output "ingress_class" {
  description = "IngressClass the RHDH chart should target."
  value       = var.ingress_class
}

output "argocd_namespace" {
  description = "Namespace ArgoCD runs in."
  value       = helm_release.argocd.namespace
}

output "argocd_admin_password_command" {
  description = "Initial ArgoCD admin password (the Secret is deleted once you change it)."
  value       = "kubectl -n ${var.argocd_namespace} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}

output "argocd_port_forward_command" {
  description = "ArgoCD UI is not exposed; reach it locally."
  value       = "kubectl -n ${var.argocd_namespace} port-forward svc/argocd-server 8080:80"
}

output "ingress_hostname_command" {
  description = <<-EOT
    The NLB hostname backing every Ingress. Point DNS at this, or use a
    *.nip.io host derived from its resolved address for a throwaway URL.
  EOT
  value       = "kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
}
