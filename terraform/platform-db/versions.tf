terraform {
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.62"
    }
  }

  # A third state key, and the most important separation of the three. The
  # database must outlive the cluster: `destroy.yml` tears the cluster down
  # routinely, and a database sharing that state would go with it every time.
  #
  # Partial configuration: bucket and region come from the file shared by every
  # root under terraform/, so initialise with
  #
  #   terraform init -backend-config=../state.s3.tfbackend
  backend "s3" {
    key          = "edx/platform-db/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
