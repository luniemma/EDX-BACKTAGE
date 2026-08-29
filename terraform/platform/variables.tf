variable "aws_region" {
  description = "Region for the platform."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Tag applied to everything this root creates."
  type        = string
  default     = "edx-backtage"
}

variable "name" {
  description = "Name prefix for the cluster and its networking."
  type        = string
  default     = "edx-rhdh"
}

variable "vpc_cidr" {
  description = "CIDR for the platform VPC. Not the default VPC — this root builds its own."
  type        = string
  default     = "10.42.0.0/16"
}

variable "az_count" {
  description = <<-EOT
    Number of availability zones. EKS requires subnets in at least two, so two
    is the floor as well as the default. Raising this adds subnets, not cost:
    there are no NAT gateways in this profile.
  EOT
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2
    error_message = "EKS requires at least two availability zones."
  }
}

variable "kubernetes_version" {
  description = "EKS control plane version."
  type        = string
  default     = "1.31"
}

variable "node_instance_types" {
  description = <<-EOT
    Candidate instance types for the Spot node group. More types means a deeper
    capacity pool and fewer interruptions, so this is a list rather than one
    type. All should be close in size or the scheduler sees an inconsistent
    cluster.
  EOT
  type        = list(string)
  default     = ["t3.medium", "t3a.medium", "t2.medium"]
}

variable "node_desired_size" {
  description = "Nodes to run. Two fits RHDH plus ArgoCD plus ingress-nginx with headroom."
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Lower bound for the node group."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Upper bound. Kept low on purpose: this profile has a cost ceiling."
  type        = number
  default     = 4
}

variable "node_disk_size" {
  description = <<-EOT
    Root volume per node, GiB. RHDH's init container unpacks every dynamic
    plugin onto the node's ephemeral storage, and values.yaml asks for a 5Gi
    ephemeral-storage limit, so this cannot be trimmed to the 20Gi default
    without risking eviction.
  EOT
  type        = number
  default     = 40
}

variable "public_access_cidrs" {
  description = <<-EOT
    Who may reach the Kubernetes API. Defaults to the whole internet because
    this profile has no NAT gateway and no bastion, so there is no private path
    in. Narrow it to your egress IP if you have a stable one — it is the single
    highest-value hardening step available in this profile.
  EOT
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "tfstate_bucket" {
  description = "Bucket holding this root's state. Must match the backend block in versions.tf."
  type        = string
  default     = "edx-backtage-tfstate-724772096574"
}

variable "github_owner" {
  description = "GitHub org/user, for the OIDC trust policy."
  type        = string
  default     = "luniemma"
}

variable "github_repo" {
  description = "GitHub repository, for the OIDC trust policy."
  type        = string
  default     = "EDX-BACKTAGE"
}

variable "terraform_apply_branches" {
  description = <<-EOT
    Branches whose workflow runs may assume the platform apply role. Keep this
    to protected branches only — membership here is write access to the
    cluster.
  EOT
  type        = list(string)
  default     = ["main"]
}

variable "extra_tags" {
  description = "Additional tags merged into the provider default_tags."
  type        = map(string)
  default     = {}
}
