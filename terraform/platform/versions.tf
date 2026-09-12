terraform {
  # >= 1.11 for S3 native state locking (use_lockfile), matching the ECR root.
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.62"
    }
  }

  # Deliberately a separate state key from the ECR/CI root. The two have
  # different blast radii and different apply roles: losing or corrupting the
  # cluster state must not be able to take the CI plumbing with it.
  #
  # Partial configuration: bucket and region come from the file shared by every
  # root under terraform/, so initialise with
  #
  #   terraform init -backend-config=../state.s3.tfbackend
  backend "s3" {
    key          = "edx/platform/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
