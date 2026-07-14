provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(
      {
        Project     = var.project
        ManagedBy   = "terraform"
        Application = "backend-api"
      },
      var.extra_tags,
    )
  }
}
