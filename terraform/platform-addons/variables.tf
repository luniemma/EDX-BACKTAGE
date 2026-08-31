variable "project" {
  description = "Tag applied to everything this root creates."
  type        = string
  default     = "edx-backtage"
}

variable "ingress_nginx_version" {
  description = "ingress-nginx chart version."
  type        = string
  default     = "4.11.3"
}

variable "argocd_version" {
  description = "argo-cd chart version."
  type        = string
  default     = "7.7.11"
}

variable "argocd_namespace" {
  description = "Namespace for ArgoCD. The Application manifests in deploy/argocd hardcode this."
  type        = string
  default     = "argocd"
}

variable "ingress_class" {
  description = <<-EOT
    Ingress class name. The RHDH chart's values set className: nginx, so
    changing this without changing the chart leaves the Ingress unclaimed and
    the portal unreachable.
  EOT
  type        = string
  default     = "nginx"
}

variable "name" {
  description = "Name prefix, matching the platform root so IAM roles stay inside the edx-rhdh-* scope the CI roles are limited to."
  type        = string
  default     = "edx-rhdh"
}

variable "external_dns_version" {
  description = "external-dns chart version."
  type        = string
  default     = "1.15.0"
}

variable "cert_manager_version" {
  description = "cert-manager chart version."
  type        = string
  default     = "v1.16.2"
}

variable "acme_email" {
  description = <<-EOT
    Contact address on the Let's Encrypt account. They mail it before a
    certificate expires unrenewed, which is the only warning you get that
    renewal has quietly broken.
  EOT
  type        = string
  default     = "platform@example.com"
}
