########################################
# Cluster coordinates, read from the platform root
########################################
# Remote state rather than data sources on the cluster itself: this root must
# fail loudly if ../platform has not been applied, instead of half-configuring
# against a cluster that does not exist.

data "terraform_remote_state" "platform" {
  backend = "s3"

  config = {
    bucket = "edx-backtage-tfstate-724772096574"
    key    = "edx/platform/terraform.tfstate"
    region = "us-east-1"
  }
}

locals {
  cluster_name     = data.terraform_remote_state.platform.outputs.cluster_name
  cluster_endpoint = data.terraform_remote_state.platform.outputs.cluster_endpoint
  cluster_ca       = data.terraform_remote_state.platform.outputs.cluster_certificate_authority_data
  region           = data.terraform_remote_state.platform.outputs.region
}

provider "aws" {
  region = local.region

  default_tags {
    tags = {
      Project     = var.project
      ManagedBy   = "terraform"
      Application = "platform-addons"
    }
  }
}

# `exec` rather than a stored token: EKS tokens last 15 minutes, so a token
# resolved at plan time is routinely expired by apply time on a slow run.
provider "kubernetes" {
  host                   = local.cluster_endpoint
  cluster_ca_certificate = base64decode(local.cluster_ca)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", local.cluster_name, "--region", local.region]
  }
}

provider "helm" {
  kubernetes {
    host                   = local.cluster_endpoint
    cluster_ca_certificate = base64decode(local.cluster_ca)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", local.cluster_name, "--region", local.region]
    }
  }
}
