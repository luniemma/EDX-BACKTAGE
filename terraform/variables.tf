variable "aws_region" {
  description = "AWS region for the ECR repository and IAM resources"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Short project name (used as tag)"
  type        = string
  default     = "backend-api"
}

variable "repository_name" {
  description = "ECR repository name"
  type        = string
  default     = "backend-api"
}

variable "image_tag_mutability" {
  description = "IMMUTABLE (recommended for prod) or MUTABLE"
  type        = string
  default     = "IMMUTABLE"
  validation {
    condition     = contains(["IMMUTABLE", "MUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be IMMUTABLE or MUTABLE."
  }
}

variable "untagged_image_expire_days" {
  description = "Delete untagged images older than N days"
  type        = number
  default     = 7
}

variable "keep_last_release_images" {
  description = "How many semver-tagged (v*) images to keep"
  type        = number
  default     = 30
}

variable "keep_last_sha_images" {
  description = "How many sha-<short> dev images to keep"
  type        = number
  default     = 50
}

# ----- GitHub OIDC (push role) -----

variable "github_owner" {
  description = "GitHub org or user that owns the repo (e.g. \"my-org\")"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (e.g. \"backend-api\")"
  type        = string
}

variable "github_push_branches" {
  description = "Branches allowed to push images. Wildcards permitted."
  type        = list(string)
  default     = ["main", "release/*"]
}

variable "github_push_tags" {
  description = "Tag patterns allowed to push images (for release workflow)"
  type        = list(string)
  default     = ["v*.*.*"]
}

variable "create_github_oidc_provider" {
  description = "Create the token.actions.githubusercontent.com OIDC provider. Set to false if it already exists in the account."
  type        = bool
  default     = true
}

# ----- Terraform's own CI roles / remote state -----

variable "tfstate_bucket" {
  description = "S3 bucket holding this stack's Terraform state. Must match the backend block in versions.tf."
  type        = string
  default     = "edx-backtage-tfstate-724772096574"
}

variable "tfstate_key" {
  description = "S3 key of this stack's state object. Must match the backend block in versions.tf."
  type        = string
  default     = "backend-api/ecr/terraform.tfstate"
}

variable "terraform_apply_branches" {
  description = "Branches allowed to assume the Terraform apply role. Keep this tight — apply can manage IAM."
  type        = list(string)
  default     = ["main"]
}

# ----- Pull side (EKS / cross-account) -----

variable "additional_pull_account_ids" {
  description = "Extra AWS account IDs allowed to pull from this repo (e.g. shared EKS cluster accounts). Leave empty for same-account only."
  type        = list(string)
  default     = []
}

variable "extra_tags" {
  description = "Extra tags applied to every resource"
  type        = map(string)
  default     = {}
}
