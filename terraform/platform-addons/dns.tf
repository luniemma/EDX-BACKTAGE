########################################
# external-dns and cert-manager
########################################
# Both are gated on the DNS root having a domain. With none set this file
# creates nothing, which keeps the default profile working exactly as before.
#
# These live here rather than in platform-dns because they need the cluster's
# OIDC provider, and putting them in the DNS root would make that root depend
# on the cluster — inverting the dependency and coupling the zone's lifecycle
# to the cluster's, which is the one thing the separate state key exists to
# prevent.

data "terraform_remote_state" "dns" {
  backend = "s3"

  config = {
    bucket = var.tfstate_bucket
    key    = var.dns_tfstate_key
    region = var.tfstate_region
  }
}

locals {
  domain    = try(data.terraform_remote_state.dns.outputs.domain_name, "")
  zone_id   = try(data.terraform_remote_state.dns.outputs.zone_id, "")
  dns_ready = local.domain != "" && local.zone_id != ""

  oidc_host = replace(
    data.terraform_remote_state.platform.outputs.cluster_oidc_issuer_url, "https://", ""
  )
}

########## external-dns IRSA role ##########

data "aws_iam_policy_document" "external_dns_assume" {
  count = local.dns_ready ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.terraform_remote_state.platform.outputs.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = ["system:serviceaccount:${var.external_dns_namespace}:external-dns"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "external_dns" {
  count = local.dns_ready ? 1 : 0

  # Write access to exactly one zone. external-dns deletes records as readily
  # as it creates them, so an unscoped policy here would let a misconfigured
  # controller empty an unrelated production zone.
  statement {
    sid       = "ChangeThisZoneOnly"
    effect    = "Allow"
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = ["arn:aws:route53:::hostedzone/${local.zone_id}"]
  }

  # Listing is account-wide because that is the only granularity Route53
  # offers for these calls — they do not accept a resource ARN.
  statement {
    sid    = "DiscoverZones"
    effect = "Allow"
    actions = [
      "route53:ListHostedZones",
      "route53:ListResourceRecordSets",
      "route53:ListTagsForResources",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role" "external_dns" {
  count = local.dns_ready ? 1 : 0

  name               = "${var.name}-external-dns"
  assume_role_policy = data.aws_iam_policy_document.external_dns_assume[0].json
  description        = "IRSA role for external-dns, scoped to one hosted zone"
}

resource "aws_iam_role_policy" "external_dns" {
  count = local.dns_ready ? 1 : 0

  name   = "${var.name}-external-dns"
  role   = aws_iam_role.external_dns[0].id
  policy = data.aws_iam_policy_document.external_dns[0].json
}

########## external-dns ##########

resource "helm_release" "external_dns" {
  count = local.dns_ready ? 1 : 0

  name             = "external-dns"
  repository       = var.external_dns_chart_repository
  chart            = "external-dns"
  version          = var.external_dns_version
  namespace        = var.external_dns_namespace
  create_namespace = true

  wait    = true
  timeout = var.dns_addons_helm_timeout_seconds

  values = [yamlencode({
    provider = { name = "aws" }

    serviceAccount = {
      create = true
      name   = "external-dns"
      annotations = {
        "eks.amazonaws.com/role-arn" = aws_iam_role.external_dns[0].arn
      }
    }

    # Confine it to the one zone it has permission for. Without this it tries
    # every zone it can list and logs a permission error per record per sync.
    domainFilters = [local.domain]
    zoneIdFilters = [local.zone_id]

    # sync, not upsert-only. upsert-only never deletes, so a record outlives
    # the Ingress that created it and the zone can never be destroyed — the
    # orphan-on-teardown problem this platform has hit twice already, in a
    # third form. sync means external-dns cleans up after itself.
    policy = "sync"

    # A TXT record alongside each managed record, marking ownership. Without
    # it external-dns cannot tell its own records from hand-made ones and
    # refuses to touch anything.
    txtOwnerId = var.name

    sources = ["ingress", "service"]

    resources = var.external_dns_resources
  })]
}

########## cert-manager ##########
# HTTP-01 rather than DNS-01, deliberately. DNS-01 would need a second IRSA
# role with Route53 write access; HTTP-01 proves control by serving a file
# over the Ingress that already exists, so it needs no AWS credentials at all.
# The trade is that DNS-01 can issue wildcards and HTTP-01 cannot — irrelevant
# here, where one hostname is served.

resource "helm_release" "cert_manager" {
  count = local.dns_ready ? 1 : 0

  name             = "cert-manager"
  repository       = var.cert_manager_chart_repository
  chart            = "cert-manager"
  version          = var.cert_manager_version
  namespace        = var.cert_manager_namespace
  create_namespace = true

  wait    = true
  timeout = var.dns_addons_helm_timeout_seconds

  values = [yamlencode({
    crds = { enabled = true }

    resources = var.cert_manager_resources
  })]
}

# The ClusterIssuer is a CRD instance, so it cannot exist until cert-manager's
# CRDs are installed — hence the explicit dependency rather than relying on
# resource ordering.
resource "kubernetes_manifest" "letsencrypt_issuer" {
  count = local.dns_ready ? 1 : 0

  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      # values-prod.yaml already names this issuer, so the name is a contract.
      name = var.cluster_issuer_name
    }
    spec = {
      acme = {
        server = var.acme_server
        email  = var.acme_email
        privateKeySecretRef = {
          name = "${var.cluster_issuer_name}-account-key"
        }
        solvers = [{
          http01 = {
            ingress = {
              ingressClassName = var.ingress_class
            }
          }
        }]
      }
    }
  }

  depends_on = [helm_release.cert_manager]
}

output "nameservers_reminder" {
  description = "Where to look if certificates never issue."
  value = local.dns_ready ? join(" ", [
    "Delegation must be live before Let's Encrypt can validate.",
    "Check: dig NS ${local.domain}",
  ]) : "DNS is disabled — set domain_name in terraform/platform-dns"
}
