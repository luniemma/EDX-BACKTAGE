terraform {
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.62"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.35"
    }
  }

  # Separate again from ../platform. Cluster-internal software changes far more
  # often than the cluster itself, and a bad addon apply should never be able
  # to touch the state that owns the VPC and the control plane.
  backend "s3" {
    bucket       = "edx-backtage-tfstate-724772096574"
    key          = "edx/platform-addons/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
