# Nothing here carries a value. Every variable is set in terraform.tfvars,
# committed next to this file, so what this deployment runs is visible in one
# place rather than scattered across defaults. The descriptions explain the
# values chosen there.

variable "project" {
  description = "Tag applied to everything this root creates."
  type        = string
}

variable "ingress_nginx_version" {
  description = "ingress-nginx chart version."
  type        = string
}

variable "argocd_version" {
  description = "argo-cd chart version."
  type        = string
}

variable "argocd_namespace" {
  description = "Namespace for ArgoCD. The Application manifests in deploy/argocd hardcode this."
  type        = string
}

variable "ingress_class" {
  description = <<-EOT
    Ingress class name. The RHDH chart's values set className: nginx, so
    changing this without changing the chart leaves the Ingress unclaimed and
    the portal unreachable.
  EOT
  type        = string
}

variable "tfstate_bucket" {
  description = <<-EOT
    Bucket holding the platform root's state, read for the cluster endpoint
    and credentials. Must match bucket in ../state.s3.tfbackend.
  EOT
  type        = string
}

variable "tfstate_region" {
  description = "Region of tfstate_bucket. Must match region in ../state.s3.tfbackend."
  type        = string
}

variable "platform_tfstate_key" {
  description = "State key of the platform root, read for the cluster's coordinates. Must match the key in ../platform/versions.tf."
  type        = string
}

variable "ingress_nginx_namespace" {
  description = <<-EOT
    Namespace for ingress-nginx. The platform and destroy workflows look for
    the controller Service by this name too, so change them together.
  EOT
  type        = string
}

variable "ingress_nginx_chart_repository" {
  description = "Helm repository ingress-nginx is installed from."
  type        = string
}

variable "argocd_chart_repository" {
  description = "Helm repository argo-cd is installed from."
  type        = string
}

variable "helm_timeout_seconds" {
  description = "How long each Helm release may take to become ready before the apply fails."
  type        = number
}

variable "ingress_nginx_replicas" {
  description = "ingress-nginx controller replicas, spread across nodes behind the one shared NLB."
  type        = number
}

variable "ingress_nginx_resources" {
  description = "ingress-nginx controller requests and limits, in the chart's resources shape."
  type = object({
    requests = map(string)
    limits   = map(string)
  })
}

variable "argocd_replicas" {
  description = "Replicas per ArgoCD component, keyed by chart value name: controller, repoServer, applicationSet, server."
  type        = map(number)
}

variable "argocd_resources" {
  description = "Requests and limits per ArgoCD component, keyed by chart value name: controller, repoServer, server."
  type = map(object({
    requests = map(string)
    limits   = map(string)
  }))
}

variable "name" {
  description = "Name prefix, matching the platform root so IAM roles stay inside the edx-rhdh-* scope the CI roles are limited to."
  type        = string
}

variable "external_dns_version" {
  description = "external-dns chart version."
  type        = string
}

variable "cert_manager_version" {
  description = "cert-manager chart version."
  type        = string
}

variable "acme_email" {
  description = <<-EOT
    Contact address on the Let's Encrypt account. They mail it before a
    certificate expires unrenewed, which is the only warning you get that
    renewal has quietly broken.
  EOT
  type        = string
}

variable "dns_tfstate_key" {
  description = "State key of the platform-dns root, read for the zone. Must match the key in ../platform-dns/versions.tf."
  type        = string
}

variable "external_dns_namespace" {
  description = "Namespace for external-dns. Its IRSA trust policy names the service account in this namespace."
  type        = string
}

variable "external_dns_chart_repository" {
  description = "Helm repository external-dns is installed from."
  type        = string
}

variable "cert_manager_namespace" {
  description = "Namespace for cert-manager."
  type        = string
}

variable "cert_manager_chart_repository" {
  description = "Helm repository cert-manager is installed from."
  type        = string
}

variable "dns_addons_helm_timeout_seconds" {
  description = "How long external-dns and cert-manager may each take to become ready before the apply fails."
  type        = number
}

variable "external_dns_resources" {
  description = "external-dns requests and limits, in the chart's resources shape."
  type = object({
    requests = map(string)
    limits   = map(string)
  })
}

variable "cert_manager_resources" {
  description = "cert-manager requests and limits, in the chart's resources shape."
  type = object({
    requests = map(string)
    limits   = map(string)
  })
}

variable "acme_server" {
  description = "ACME directory the ClusterIssuer registers with and requests certificates from."
  type        = string
}

variable "cluster_issuer_name" {
  description = <<-EOT
    Name of the cert-manager ClusterIssuer. values-prod.yaml already names this
    issuer, so the name is a contract: change both together.
  EOT
  type        = string
}
