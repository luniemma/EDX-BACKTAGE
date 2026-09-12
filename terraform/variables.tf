# Nothing here carries a value. Every variable is set in terraform.tfvars,
# committed next to this file, so what this deployment runs is visible in one
# place rather than scattered across defaults. Only optional collections that
# stay empty unless populated keep a default.

variable "aws_region" {
  description = "AWS region for the ECR repository and IAM resources"
  type        = string
}

variable "project" {
  description = "Short project name (used as tag)"
  type        = string
}

variable "repository_name" {
  description = "ECR repository name"
  type        = string
}

variable "image_tag_mutability" {
  description = "IMMUTABLE (recommended for prod) or MUTABLE"
  type        = string
  validation {
    condition     = contains(["IMMUTABLE", "MUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be IMMUTABLE or MUTABLE."
  }
}

variable "untagged_image_expire_days" {
  description = "Delete untagged images older than N days"
  type        = number
}

variable "keep_last_release_images" {
  description = "How many semver-tagged (v*) images to keep"
  type        = number
}

variable "keep_last_sha_images" {
  description = "How many sha-<short> dev images to keep"
  type        = number
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
}

variable "github_push_tags" {
  description = "Tag patterns allowed to push images (for release workflow)"
  type        = list(string)
}

variable "create_github_oidc_provider" {
  description = "Create the token.actions.githubusercontent.com OIDC provider. Set to false if it already exists in the account."
  type        = bool
}

# ----- Terraform's own CI roles / remote state -----

variable "tfstate_bucket" {
  description = "S3 bucket holding this stack's Terraform state. Must match bucket in state.s3.tfbackend."
  type        = string
}

variable "tfstate_key" {
  description = "S3 key of this stack's state object. Must match the backend block in versions.tf."
  type        = string
}

variable "terraform_apply_branches" {
  description = "Branches allowed to assume the Terraform apply role. Keep this tight — apply can manage IAM."
  type        = list(string)
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

variable "release_image_tag_patterns" {
  description = "Tag patterns marking release images, of which keep_last_release_images are kept. Should cover what github_push_tags produces."
  type        = list(string)
}

variable "dev_image_tag_patterns" {
  description = "Tag patterns marking per-commit dev images, of which keep_last_sha_images are kept."
  type        = list(string)
}
