terraform {
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.62"
    }
  }

  # A fourth state key. The zone must outlive the cluster by an even wider
  # margin than the database does: destroying it means re-delegating
  # nameservers at the registrar and waiting out DNS propagation, which is the
  # one part of this stack that cannot be fixed by re-running a workflow.
  #
  # Partial configuration: bucket and region come from the file shared by every
  # root under terraform/, so initialise with
  #
  #   terraform init -backend-config=../state.s3.tfbackend
  backend "s3" {
    key          = "edx/platform-dns/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
