########################################
# DNS zone
########################################
# Deliberately not the domain registration. aws_route53domains_registered_domain
# exists, and it is the wrong tool: registration is a purchase, paid a year
# ahead, and Terraform will happily plan a destroy it cannot perform. Register
# the domain wherever you like and delegate its nameservers here — this root
# owns the zone and everything under it, and nothing it creates costs more than
# $0.50/month or takes longer than a propagation window to undo.
#
# Everything here is gated on var.domain_name. It is empty in terraform.tfvars,
# so this root applies cleanly and creates nothing until someone supplies one.

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      ManagedBy   = "terraform"
      Application = "platform-dns"
    }
  }
}

locals {
  enabled = var.domain_name != ""
}

resource "aws_route53_zone" "this" {
  count = local.enabled ? 1 : 0

  name    = var.domain_name
  comment = "Managed by terraform/platform-dns"

  # No force_destroy. If records exist that Terraform did not create — which is
  # exactly what external-dns produces — the destroy fails with "HostedZone is
  # not empty", and that failure is the point. Silently deleting records for a
  # domain that may still be serving traffic is worse than a failed destroy.
  # destroy.yml removes external-dns first so it cleans up its own records.
  force_destroy = false
}

output "zone_id" {
  description = "Hosted zone id. platform-addons scopes the external-dns IAM policy to this."
  value       = local.enabled ? aws_route53_zone.this[0].zone_id : ""
}

output "zone_arn" {
  description = "Hosted zone ARN."
  value       = local.enabled ? aws_route53_zone.this[0].arn : ""
}

output "domain_name" {
  description = "The domain, echoed so downstream roots do not need the variable too."
  value       = var.domain_name
}

output "nameservers" {
  description = <<-EOT
    Set these at the registrar. Nothing works until the delegation is live —
    check with `dig NS <domain>` and expect these four back.
  EOT
  value       = local.enabled ? aws_route53_zone.this[0].name_servers : []
}
