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

variable "backstage_host" {
  description = "Hostname Backstage is served on."
  type        = string
  default     = "backstage.dev.local"
}

variable "backstage_namespace" {
  description = "Namespace the Backstage TLS secret is created in (must match the app)."
  type        = string
  default     = "backstage-dev"
}

variable "argocd_host" {
  description = "Hostname the ArgoCD UI is served on."
  type        = string
  default     = "argocd.dev.local"
}

variable "argocd_namespace" {
  description = "Namespace ArgoCD runs in."
  type        = string
  default     = "argocd"
}
