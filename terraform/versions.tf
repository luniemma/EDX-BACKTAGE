terraform {
  # >= 1.11 for S3 native state locking (use_lockfile), which replaces the
  # old DynamoDB lock table.
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }

  backend "s3" {
    bucket       = "edx-backtage-tfstate-724772096574"
    key          = "backend-api/ecr/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
