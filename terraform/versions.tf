terraform {
  # >= 1.11 for S3 native state locking (use_lockfile), which replaces the
  # old DynamoDB lock table.
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.62"
    }
  }

  # Partial configuration: bucket and region come from state.s3.tfbackend,
  # shared by every root under terraform/, so initialise with
  #
  #   terraform init -backend-config=state.s3.tfbackend
  backend "s3" {
    key          = "backend-api/ecr/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
