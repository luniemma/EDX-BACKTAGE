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
  backend "s3" {
    bucket       = "edx-backtage-tfstate-724772096574"
    key          = "edx/platform/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
