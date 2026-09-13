# Nothing here carries a value. Every variable is set in terraform.tfvars,
# committed next to this file, so what this deployment runs is visible in one
# place rather than scattered across defaults. The descriptions explain the
# values chosen there. Only optional collections that stay empty unless
# populated keep a default.

variable "aws_region" {
  description = "Region for the platform."
  type        = string
}

variable "project" {
  description = "Tag applied to everything this root creates."
  type        = string
}

variable "name" {
  description = <<-EOT
    Name prefix for the cluster and its networking, and the prefix the CI
    roles' IAM permissions are scoped to.

    The workflows take the cluster name from terraform.tfvars too (see
    .github/actions/cluster-name), so it is set in exactly one place.
  EOT
  type        = string
}

variable "vpc_cidr" {
  description = <<-EOT
    CIDR for the platform VPC. Not the default VPC — this root builds its own.

    No default, because the right range depends on what else is routed in the
    account — peering, VPN, other VPCs — and an overlap stays silent until
    something tries to connect. Subnets are carved from it subnet_newbits
    smaller, public from index 0 and private from private_subnet_offset; the
    validation below checks that they fit and are no smaller than /28.
  EOT
  type        = string

  validation {
    condition = can(cidrnetmask(var.vpc_cidr)) && try(
      tonumber(split("/", var.vpc_cidr)[1]) + var.subnet_newbits <= 28 &&
      var.private_subnet_offset + var.az_count <= pow(2, var.subnet_newbits),
      false
    )
    error_message = "vpc_cidr must be IPv4 and hold private_subnet_offset + az_count subnets of subnet_newbits smaller, each /28 or larger."
  }
}

variable "az_count" {
  description = <<-EOT
    Number of availability zones. EKS requires subnets in at least two, so two
    is the floor. Raising this adds subnets, not cost:
    there are no NAT gateways in this profile.
  EOT
  type        = number

  validation {
    condition     = var.az_count >= 2
    error_message = "EKS requires at least two availability zones."
  }
}

variable "kubernetes_version" {
  description = "EKS control plane version."
  type        = string
}

variable "node_instance_types" {
  description = <<-EOT
    Candidate instance types for the Spot node group. More types means a deeper
    capacity pool and fewer interruptions, so this is a list rather than one
    type. All should be close in size or the scheduler sees an inconsistent
    cluster.
  EOT
  type        = list(string)
}

variable "node_desired_size" {
  description = "Nodes to run. Two fits RHDH plus ArgoCD plus ingress-nginx with headroom."
  type        = number
}

variable "node_min_size" {
  description = "Lower bound for the node group."
  type        = number
}

variable "node_max_size" {
  description = "Upper bound. Kept low on purpose: this profile has a cost ceiling."
  type        = number
}

variable "node_disk_size" {
  description = <<-EOT
    Root volume per node, GiB.

    Sized from what actually lands on it, not a round number: the AL2023 image
    (~3 GiB), the RHDH image (~2 GiB) and its unpacked dynamic plugins, plus
    the 5Gi ephemeral-storage limit values.yaml requests. That is ~12 GiB in
    use, so 30 leaves better than 2x headroom while costing a third less than
    the 40 this started at.

    The AMI default of 20 is genuinely too small — the plugin unpack evicts
    the pod under it.
  EOT
  type        = number

  validation {
    condition     = var.node_disk_size >= 25
    error_message = "Below ~25 GiB the RHDH plugin unpack risks disk-pressure eviction."
  }
}

variable "cluster_admin_principals" {
  description = <<-EOT
    IAM principals that hold cluster-admin in addition to the CI apply role,
    which always does. Empty by default, because the right list is
    account-specific and a wrong ARN here is a broken apply rather than a
    warning.

    Populate it with the humans and roles that need kubectl — nothing else
    grants it. Admin does not follow whoever ran the last apply, so a local
    identity needs to be listed here, including the one running the first,
    local bootstrap apply of platform-addons. Granting access by hand works but
    is drift the next apply undoes, so it has to be declared.

      cluster_admin_principals = [
        "arn:aws:iam::724772096574:user/terra-project",
      ]
  EOT
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for a in var.cluster_admin_principals : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:(user|role)/", a))])
    error_message = "Each entry must be an IAM user or role ARN."
  }
}

variable "enabled_cluster_log_types" {
  description = <<-EOT
    Control plane logs shipped to CloudWatch, billed per GiB ingested.

    The module's default adds "audit", which logs every single API call and is
    by far the chattiest of the three — on an idle cluster it is most of the
    log bill on its own. It is dropped here because this is an evaluation
    cluster that gets torn down, and "api" plus "authenticator" still answer
    the questions that actually come up: did the control plane accept this,
    and who was it.

    Put "audit" back before this holds anything you would need to investigate
    after the fact. It is a real security signal, not padding.
  EOT
  type        = list(string)
}

variable "public_access_cidrs" {
  description = <<-EOT
    Who may reach the Kubernetes API. Set to the whole internet because
    this profile has no NAT gateway and no bastion, so there is no private path
    in. Narrow it to your egress IP if you have a stable one — it is the single
    highest-value hardening step available in this profile.
  EOT
  type        = list(string)
}

variable "tfstate_bucket" {
  description = <<-EOT
    Bucket holding the platform roots' state, which the CI roles are granted
    access to.

    Must match bucket in ../state.s3.tfbackend. Terraform does not read
    variables into backend configuration, so the two are kept in step by hand.
  EOT
  type        = string
}

variable "github_owner" {
  description = "GitHub org/user, for the OIDC trust policy."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository, for the OIDC trust policy."
  type        = string
}

variable "terraform_apply_branches" {
  description = <<-EOT
    Branches whose workflow runs may assume the platform apply role. Keep this
    to protected branches only — membership here is write access to the
    cluster.
  EOT
  type        = list(string)
}

variable "extra_tags" {
  description = "Additional tags merged into the provider default_tags."
  type        = map(string)
  default     = {}
}

variable "subnet_newbits" {
  description = <<-EOT
    How much smaller than vpc_cidr each subnet is, in prefix bits: 4 turns a
    /16 into /20s, 4091 usable addresses each. The VPC CNI hands a VPC address
    to every pod, so subnets need to be generous relative to pod count, not
    node count.
  EOT
  type        = number
}

variable "private_subnet_offset" {
  description = <<-EOT
    Subnet index the private subnets start at, so public and private never
    collide as az_count grows.
  EOT
  type        = number

  validation {
    condition     = var.private_subnet_offset >= var.az_count
    error_message = "private_subnet_offset must be at least az_count, or public and private subnets overlap."
  }
}

variable "cluster_log_retention_days" {
  description = "Days CloudWatch keeps the control-plane logs listed in enabled_cluster_log_types."
  type        = number
}

variable "node_capacity_type" {
  description = <<-EOT
    SPOT or ON_DEMAND. Spot is roughly $40/month cheaper for this node group,
    and nodes get reclaimed: RHDH is a stateless Deployment and ArgoCD
    re-places what gets evicted, which is what makes that survivable.
  EOT
  type        = string

  validation {
    condition     = contains(["SPOT", "ON_DEMAND"], var.node_capacity_type)
    error_message = "node_capacity_type must be SPOT or ON_DEMAND."
  }
}

variable "node_volume_type" {
  description = "EBS volume type for node root volumes."
  type        = string
}

variable "node_labels" {
  description = "Kubernetes labels applied to every node in the group."
  type        = map(string)
}

variable "platform_tfstate_keys" {
  description = <<-EOT
    State keys of the platform, platform-addons and platform-db roots. The CI
    roles are granted these objects and their lock files, and nothing else in
    the bucket. Each must match the key in that root's versions.tf.
  EOT
  type        = list(string)
}

variable "alert_emails" {
  description = <<-EOT
    Addresses subscribed to the alerts topic and to the budget. Each gets a
    confirmation mail from AWS and receives nothing until the link in it is
    followed. Empty still creates the topic and the alarms, with no one
    listening, and the budget with no notifications.

    This repository is public: an address committed here is published.
  EOT
  type        = list(string)

  validation {
    condition     = alltrue([for e in var.alert_emails : can(regex("^[^@ ]+@[^@ ]+[.][^@ ]+$", e))])
    error_message = "Each alert_emails entry must be an email address."
  }
}

variable "notify_on_recovery" {
  description = "Also notify when an alarm returns to OK, so every alert has a matching all-clear."
  type        = bool
}

variable "alerts_kms_deletion_window_days" {
  description = "Waiting period, 7 to 30 days, before the alerts topic's KMS key is deleted once destroyed. It can be recovered until then."
  type        = number

  validation {
    condition     = var.alerts_kms_deletion_window_days >= 7 && var.alerts_kms_deletion_window_days <= 30
    error_message = "KMS accepts a deletion window of 7 to 30 days."
  }
}

variable "monthly_budget_usd" {
  description = "Monthly AWS cost for the whole account, in USD. budget_notifications are percentages of this."
  type        = number

  validation {
    condition     = var.monthly_budget_usd > 0
    error_message = "monthly_budget_usd must be greater than zero."
  }
}

variable "budget_notifications" {
  description = <<-EOT
    When the budget mails alert_emails, as a percentage of monthly_budget_usd.
    ACTUAL fires on spend already incurred; FORECASTED fires when AWS projects
    the month will end over the threshold, which is the earlier warning.
  EOT
  type = list(object({
    notification_type = string
    threshold_percent = number
  }))

  validation {
    condition     = alltrue([for n in var.budget_notifications : contains(["ACTUAL", "FORECASTED"], n.notification_type) && n.threshold_percent > 0])
    error_message = "Each budget_notifications entry needs notification_type ACTUAL or FORECASTED and a threshold_percent above zero."
  }
}

variable "node_alarms" {
  description = <<-EOT
    CloudWatch alarms on the node group, keyed by a short name that becomes
    part of the alarm name. Each is evaluated across every node in the group
    through the AutoScalingGroupName dimension. Thresholds are in the metric's
    own CloudWatch unit.
  EOT
  type = map(object({
    namespace           = string
    metric_name         = string
    statistic           = string
    comparison_operator = string
    threshold           = number
    period              = number
    evaluation_periods  = number
    treat_missing_data  = string
    description         = string
  }))

  validation {
    condition = alltrue([
      for a in values(var.node_alarms) :
      contains(["GreaterThanOrEqualToThreshold", "GreaterThanThreshold", "LessThanThreshold", "LessThanOrEqualToThreshold"], a.comparison_operator) &&
      contains(["SampleCount", "Average", "Sum", "Minimum", "Maximum"], a.statistic) &&
      contains(["missing", "ignore", "breaching", "notBreaching"], a.treat_missing_data) &&
      a.period >= 60 && a.evaluation_periods >= 1
    ])
    error_message = "Each node_alarms entry needs a threshold comparison_operator, a basic statistic (SampleCount, Average, Sum, Minimum, Maximum), a treat_missing_data of missing/ignore/breaching/notBreaching, period >= 60 and evaluation_periods >= 1."
  }
}
