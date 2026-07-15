aws_region      = "us-east-1"
project         = "backend-api"
repository_name = "backend-api"

github_owner = "luniemma"
github_repo  = "EDX-BACKTAGE"

github_push_branches = ["main", "release/*"]
github_push_tags     = ["v*.*.*"]

# The token.actions.githubusercontent.com provider already exists in account
# 724772096574; only one per account is allowed, so adopt it rather than create.
create_github_oidc_provider = false

additional_pull_account_ids = []

extra_tags = {
  Environment = "shared"
  Owner       = "platform"
}
