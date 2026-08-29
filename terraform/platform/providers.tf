provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(
      {
        Project     = var.project
        ManagedBy   = "terraform"
        Application = "platform"
      },
      var.extra_tags,
    )
  }
}

# No kubernetes or helm provider here on purpose. Configuring one against a
# cluster created in the same apply makes the provider's own config depend on
# an unknown value, which breaks plan on a clean state and makes destroy
# unreliable. Cluster-internal software lives in ../platform-addons, which
# reads this root's outputs over remote state.
