variable "project" {
  description = "Tag applied to everything this root creates."
  type        = string
  default     = "edx-backtage"
}

variable "name" {
  description = "Name prefix. Matches the platform root so the two read as one stack."
  type        = string
  default     = "edx-rhdh"
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
  default     = "15"

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
  default     = "db.t4g.micro"
}

variable "allocated_storage" {
  description = "GiB. Below 20 RDS refuses to create a gp3 volume."
  type        = number
  default     = 20

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
  default     = 7

  validation {
    condition     = var.backup_retention_days >= 1
    error_message = "Set at least 1 day; 0 disables automated backups entirely."
  }
}

variable "multi_az" {
  description = <<-EOT
    Off by default: Multi-AZ doubles the instance cost for a standby this
    profile does not justify. Turn it on before anything depends on the
    portal being available during an AZ failure.
  EOT
  type        = bool
  default     = false
}

variable "deletion_protection" {
  description = <<-EOT
    Off by default so `terraform destroy` works without a two-step dance,
    which suits an evaluation stack. Turn it on the moment the catalog holds
    anything anyone would miss.
  EOT
  type        = bool
  default     = false
}

variable "db_name" {
  description = "Initial database. RHDH creates its own per-plugin databases alongside it."
  type        = string
  default     = "backstage"
}

variable "db_username" {
  description = "Master user. values-lean.yaml must name the same user."
  type        = string
  default     = "backstage"
}
