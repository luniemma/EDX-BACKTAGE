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
    # gavinbunney/kubectl applies raw CRD manifests without validating the CRD
    # at plan time. cert-manager's Issuer/Certificate CRDs don't exist until
    # its Helm release is applied, so hashicorp/kubernetes_manifest — which
    # dry-runs against the API at plan — can't be used for them here.
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
  }

  # Local-only stack against minikube. State stays on disk on purpose — this
  # manages nothing in AWS and is safe to `terraform destroy` and recreate.
}
