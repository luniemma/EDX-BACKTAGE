terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }

  # Configure remote state before running in a team setting. Example:
  #
  # backend "s3" {
  #   bucket         = "my-tfstate-bucket"
  #   key            = "backend-api/ecr/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "tfstate-locks"
  #   encrypt        = true
  # }
}
