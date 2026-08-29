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
