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

# Alerts. The topic, its KMS key and the budget survive a cluster teardown; the
# node alarms go with the node group.
#
# alert_emails is empty on purpose: this repository is public, so an address
# committed here is published. Nothing is delivered until it has entries.
alert_emails                    = []
notify_on_recovery              = true
alerts_kms_deletion_window_days = 7

# The whole account, in USD. The lean profile runs at roughly $130/month while
# deployed, so at $10 the budget alerts whenever the stack is up.
monthly_budget_usd = 10
budget_notifications = [
  { notification_type = "FORECASTED", threshold_percent = 100 },
  { notification_type = "ACTUAL", threshold_percent = 80 },
  { notification_type = "ACTUAL", threshold_percent = 100 },
]

node_alarms = {
  cpu_high = {
    namespace           = "AWS/EC2"
    metric_name         = "CPUUtilization"
    statistic           = "Average"
    comparison_operator = "GreaterThanThreshold"
    threshold           = 80 # percent
    period              = 300
    evaluation_periods  = 3
    treat_missing_data  = "missing"
    description         = "Average CPU across the node group has been above 80% for 15 minutes."
  }
  status_check_failed = {
    namespace           = "AWS/EC2"
    metric_name         = "StatusCheckFailed"
    statistic           = "Maximum"
    comparison_operator = "GreaterThanThreshold"
    threshold           = 0 # 1 means a failed check
    period              = 60
    evaluation_periods  = 5
    treat_missing_data  = "missing"
    description         = "At least one node has failed an EC2 status check for 5 minutes."
  }
}
