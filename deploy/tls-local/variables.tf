variable "kube_context" {
  description = "kubeconfig context to target. Must be the local minikube cluster."
  type        = string
  default     = "minikube"
}

variable "kube_config_path" {
  description = "Path to the kubeconfig file."
  type        = string
  default     = "~/.kube/config"
}

variable "cert_manager_version" {
  description = "cert-manager Helm chart version."
  type        = string
  default     = "v1.16.2"
}

# nip.io is public wildcard DNS: <anything>.127.0.0.1.nip.io resolves to
# 127.0.0.1. That avoids editing the Windows hosts file, which needs
# Administrator. Set these to *.dev.local instead if you would rather add hosts
# entries and keep everything offline.
variable "backstage_host" {
  description = "Hostname Backstage is served on."
  type        = string
  default     = "backstage.127.0.0.1.nip.io"
}

variable "backstage_namespace" {
  description = "Namespace the Backstage TLS secret is created in (must match the app)."
  type        = string
  default     = "backstage-dev"
}

variable "argocd_host" {
  description = "Hostname the ArgoCD UI is served on."
  type        = string
  default     = "argocd.127.0.0.1.nip.io"
}

variable "argocd_namespace" {
  description = "Namespace ArgoCD runs in."
  type        = string
  default     = "argocd"
}

variable "ingress_local_port" {
  description = "Local port the ingress controller is port-forwarded to. A high port is used so binding it does not need Administrator."
  type        = number
  default     = 8443
}
