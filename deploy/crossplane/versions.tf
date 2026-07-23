terraform {
  required_version = ">= 1.6.0"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.13"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
    }
    # Same reason as deploy/tls-local: Crossplane's Provider/XRD/Composition
    # CRDs do not exist until the Crossplane Helm release is applied, and
    # hashicorp/kubernetes_manifest dry-runs against the API at plan time.
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
  }
}
