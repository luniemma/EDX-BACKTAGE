# Every value this root runs with. variables.tf carries no defaults, so this
# file is the whole description of the deployment.
#
# Committed on purpose, like terraform/terraform.tfvars: it holds no secrets,
# and the plan, apply and drift jobs run in this directory, where Terraform
# loads it automatically. Never put secrets here.

aws_region = "us-east-1"
project    = "edx-backtage"

# Also the IAM prefix the CI roles are scoped to, and the cluster name the
# workflows read (.github/actions/cluster-name).
name = "edx-rhdh"

# Must match bucket in ../state.s3.tfbackend.
tfstate_bucket = "edx-backtage-tfstate-724772096574"

# Each must match the key in that root's versions.tf.
platform_tfstate_keys = [
  "edx/platform/terraform.tfstate",
  "edx/platform-addons/terraform.tfstate",
  "edx/platform-db/terraform.tfstate",
  "edx/platform-dns/terraform.tfstate",
]

github_owner             = "luniemma"
github_repo              = "EDX-BACKTAGE"
terraform_apply_branches = ["main"]

# Networking
vpc_cidr = "10.42.0.0/16"
az_count = 2

subnet_newbits        = 4
private_subnet_offset = 8

# Control plane
kubernetes_version         = "1.31"
enabled_cluster_log_types  = ["api", "authenticator"]
public_access_cidrs        = ["0.0.0.0/0"]
cluster_log_retention_days = 7

# Nodes
node_instance_types = ["t3.medium", "t3a.medium", "t2.medium"]
node_desired_size   = 2
node_min_size       = 2
node_max_size       = 4
node_disk_size      = 30
node_capacity_type  = "SPOT"
node_volume_type    = "gp3"

node_labels = {
  workload = "general"
}
