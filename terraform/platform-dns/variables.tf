# Nothing here carries a value. Every variable is set in terraform.tfvars,
# committed next to this file, so what this deployment runs is visible in one
# place rather than scattered across defaults.

variable "domain_name" {
  description = <<-EOT
    The domain this platform serves from, e.g. "example.com". Empty disables
    the whole root — no zone, no records, no cost.

    Delegate this domain's nameservers to the values in the `nameservers`
    output after the first apply. Until that delegation happens the zone
    answers only itself and certificate issuance will fail, which looks like a
    cert-manager problem and is not.
  EOT
  type        = string
}

variable "project" {
  description = "Tag applied to everything this root creates."
  type        = string
}

variable "aws_region" {
  description = "Region for the provider. Route53 is global; this only sets where API calls go."
  type        = string
}
