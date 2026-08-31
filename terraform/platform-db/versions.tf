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
  backend "s3" {
    bucket       = "edx-backtage-tfstate-724772096574"
    key          = "edx/platform-db/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
