# Every value this root runs with. variables.tf carries no defaults, so this
# file is the whole description of the deployment. Committed on purpose: it
# holds no secrets. Never put secrets here.

aws_region      = "us-east-1"
project         = "backend-api"
repository_name = "backend-api"

# Image retention
image_tag_mutability       = "IMMUTABLE"
untagged_image_expire_days = 7
keep_last_release_images   = 30
keep_last_sha_images       = 50
release_image_tag_patterns = ["v*"]
dev_image_tag_patterns     = ["sha-*"]

github_owner = "luniemma"
github_repo  = "EDX-BACKTAGE"

github_push_branches = ["main", "release/*"]
github_push_tags     = ["v*.*.*"]

# The token.actions.githubusercontent.com provider already exists in account
# 724772096574; only one per account is allowed, so adopt it rather than create.
create_github_oidc_provider = false

# This root's own state. The bucket must match state.s3.tfbackend and the key
# the backend block in versions.tf; both are granted to the CI roles.
tfstate_bucket           = "edx-backtage-tfstate-724772096574"
tfstate_key              = "backend-api/ecr/terraform.tfstate"
terraform_apply_branches = ["main"]

additional_pull_account_ids = []

extra_tags = {
  Environment = "shared"
  Owner       = "platform"
}
