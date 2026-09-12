provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(
      {
        Project     = var.project
        ManagedBy   = "terraform"
        Application = var.repository_name
      },
      var.extra_tags,
    )
  }
}
