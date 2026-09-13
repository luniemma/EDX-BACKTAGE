# Nothing here carries a value. Every variable is set in terraform.tfvars,
# committed next to this file, so what this deployment runs is visible in one
# place rather than scattered across defaults. The descriptions explain the
# values chosen there.

variable "project" {
  description = "Tag applied to everything this root creates."
  type        = string
}

variable "name" {
  description = "Name prefix. Matches the platform root so the two read as one stack."
  type        = string
}

variable "engine_version" {
  description = <<-EOT
    PostgreSQL MAJOR version only, deliberately not major.minor.

    RDS retires minor versions continuously, so a pinned patch rots: "15.8"
    was pinned here and did not exist in us-east-1 at all, which failed the
    apply with

      InvalidParameterCombination: Cannot find version 15.8 for postgres

    Given a bare major, RDS selects its current default minor and
    auto_minor_version_upgrade keeps it patched. The AWS provider does prefix
    matching on this field, so "15" does not diff against a running 15.19.

    15 matches the quay.io/fedora/postgresql-15 image the in-cluster profile
    ran, so the RHDH schema behaves identically.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.engine_version))
    error_message = "Use the major version only (e.g. \"15\"); pinned minors are retired by RDS and rot."
  }
}

variable "instance_class" {
  description = <<-EOT
    db.t4g.micro is the smallest Graviton instance RDS offers for PostgreSQL:
    2 vCPU burstable, 1 GiB RAM, ~$12/month. RHDH's catalog is small and its
    query pattern is light, so the constraint here is memory during plugin
    migrations rather than sustained throughput.
  EOT
  type        = string
}

variable "allocated_storage" {
  description = "GiB. Below 20 RDS refuses to create a gp3 volume."
  type        = number

  validation {
    condition     = var.allocated_storage >= 20
    error_message = "RDS requires at least 20 GiB for gp3 storage."
  }
}

variable "backup_retention_days" {
  description = <<-EOT
    Days of automated backups. The whole reason to move off the in-cluster pod
    is that it had none, so 0 would defeat the exercise. 7 is the smallest
    retention that survives a bad week rather than a bad afternoon.
  EOT
  type        = number

  validation {
    condition     = var.backup_retention_days >= 1
    error_message = "Set at least 1 day; 0 disables automated backups entirely."
  }
}

variable "multi_az" {
  description = <<-EOT
    Off: Multi-AZ doubles the instance cost for a standby this
    profile does not justify. Turn it on before anything depends on the
    portal being available during an AZ failure.
  EOT
  type        = bool
}

variable "deletion_protection" {
  description = <<-EOT
    Off so `terraform destroy` works without a two-step dance,
    which suits an evaluation stack. Turn it on the moment the catalog holds
    anything anyone would miss.
  EOT
  type        = bool
}

variable "db_name" {
  description = "Initial database. RHDH creates its own per-plugin databases alongside it."
  type        = string
}

variable "db_username" {
  description = "Master user. values-lean.yaml must name the same user."
  type        = string
}

variable "tfstate_bucket" {
  description = <<-EOT
    Bucket holding the platform root's state, read for the VPC, subnets and
    node security group. Must match bucket in ../state.s3.tfbackend.
  EOT
  type        = string
}

variable "tfstate_region" {
  description = "Region of tfstate_bucket. Must match region in ../state.s3.tfbackend."
  type        = string
}

variable "platform_tfstate_key" {
  description = "State key of the platform root, read for its outputs. Must match the key in ../platform/versions.tf."
  type        = string
}

variable "db_port" {
  description = "Port PostgreSQL listens on. The security group opens exactly this port, to the nodes only."
  type        = number
}

variable "max_allocated_storage" {
  description = <<-EOT
    GiB. Ceiling for RDS storage autoscaling, which grows the volume without
    downtime when it runs low. Must be at least allocated_storage.
  EOT
  type        = number

  validation {
    condition     = var.max_allocated_storage >= var.allocated_storage
    error_message = "max_allocated_storage must be at least allocated_storage."
  }
}

variable "storage_type" {
  description = "EBS volume type for the instance."
  type        = string
}

variable "backup_window" {
  description = "Daily automated-backup window, UTC, e.g. \"07:00-08:00\". Must not overlap maintenance_window."
  type        = string
}

variable "maintenance_window" {
  description = "Weekly maintenance window, UTC, e.g. \"Mon:08:30-Mon:09:30\"."
  type        = string
}

variable "apply_immediately" {
  description = "false rolls modifications into maintenance_window instead of applying them at once."
  type        = bool
}

variable "cloudwatch_logs_exports" {
  description = <<-EOT
    Log types exported to CloudWatch. `upgrade` is not a valid export type for
    this engine, and RDS rejects the whole create if it is listed.
  EOT
  type        = list(string)
}

variable "performance_insights_enabled" {
  description = "Performance Insights. Not free on burstable instance classes."
  type        = bool
}

variable "rhdh_namespace" {
  description = "Namespace RHDH runs in, where kubernetes_secret_command writes the password."
  type        = string
}

variable "rhdh_db_secret_name" {
  description = "Secret kubernetes_secret_command writes the password into. The RHDH chart values must read the same one."
  type        = string
}

variable "notify_on_recovery" {
  description = "Also notify when an alarm returns to OK, so every alert has a matching all-clear."
  type        = bool
}

variable "db_alarms" {
  description = <<-EOT
    CloudWatch alarms on the instance, keyed by a short name that becomes part
    of the alarm name. Thresholds are in the metric's own CloudWatch unit —
    FreeStorageSpace and FreeableMemory are bytes, not megabytes.
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
      for a in values(var.db_alarms) :
      contains(["GreaterThanOrEqualToThreshold", "GreaterThanThreshold", "LessThanThreshold", "LessThanOrEqualToThreshold"], a.comparison_operator) &&
      contains(["SampleCount", "Average", "Sum", "Minimum", "Maximum"], a.statistic) &&
      contains(["missing", "ignore", "breaching", "notBreaching"], a.treat_missing_data) &&
      a.period >= 60 && a.evaluation_periods >= 1
    ])
    error_message = "Each db_alarms entry needs a threshold comparison_operator, a basic statistic (SampleCount, Average, Sum, Minimum, Maximum), a treat_missing_data of missing/ignore/breaching/notBreaching, period >= 60 and evaluation_periods >= 1."
  }
}

variable "iam_database_authentication_enabled" {
  description = <<-EOT
    Allow IAM database authentication on the instance. Password logins keep
    working alongside it, and RHDH keeps using its password.

    The switch alone lets nobody in. A token login also needs, per database
    user, `GRANT rds_iam TO <user>;` — after which that user can no longer log
    in with a password — and, per IAM principal, rds-db:connect on
    arn:aws:rds-db:<region>:<account>:dbuser:<DbiResourceId>/<user>. Tokens
    are made with `aws rds generate-db-auth-token` and last 15 minutes.
  EOT
  type        = bool
}
