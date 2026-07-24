########################################
# Safety guard
########################################
data "kubernetes_nodes" "this" {}

check "is_minikube" {
  assert {
    condition     = contains([for n in data.kubernetes_nodes.this.nodes : n.metadata[0].name], "minikube")
    error_message = "This stack is local-only; the target cluster does not look like minikube."
  }
}

########################################
# Crossplane
########################################
resource "helm_release" "crossplane" {
  name             = "crossplane"
  repository       = "https://charts.crossplane.io/stable"
  chart            = "crossplane"
  version          = var.crossplane_version
  namespace        = "crossplane-system"
  create_namespace = true

  # Crossplane installs its own CRDs and controllers; give it room to settle
  # before the Provider objects below are applied.
  wait    = true
  timeout = 600
}

########################################
# Cloud providers
########################################
# Only the ECR provider is installed rather than the whole AWS family — the
# family is enormous and each provider is a separate controller pod. Add more
# provider-aws-<service> packages as they are actually needed.
resource "kubectl_manifest" "provider_aws_ecr" {
  count      = var.install_aws_provider ? 1 : 0
  depends_on = [helm_release.crossplane]

  yaml_body = <<-YAML
    apiVersion: pkg.crossplane.io/v1
    kind: Provider
    metadata:
      name: provider-aws-ecr
    spec:
      package: xpkg.upbound.io/upbound/provider-aws-ecr:v2.6.2
  YAML
}

resource "kubectl_manifest" "provider_azure" {
  count      = var.install_azure_provider ? 1 : 0
  depends_on = [helm_release.crossplane]

  yaml_body = <<-YAML
    apiVersion: pkg.crossplane.io/v1
    kind: Provider
    metadata:
      name: provider-azure-containerregistry
    spec:
      package: xpkg.upbound.io/upbound/provider-azure-containerregistry:v2.6.0
  YAML
}

########################################
# AWS credentials (off by default)
########################################
# Crossplane runs in-cluster and cannot use your local AWS CLI session, so it
# needs credentials of its own. On a real cluster this should be IRSA / Pod
# Identity, never a static key. minikube has no AWS identity, so a static key
# is the only option here — which is exactly why this is opt-in and why the
# key should be short-lived and tightly scoped.
resource "kubernetes_secret" "aws_creds" {
  count = var.enable_aws_provider_config ? 1 : 0

  metadata {
    name      = "aws-creds"
    namespace = "crossplane-system"
  }

  # Read from the environment at apply time; never committed.
  data = {
    creds = <<-CREDS
      [default]
      aws_access_key_id = ${var.aws_access_key_id}
      aws_secret_access_key = ${var.aws_secret_access_key}
    CREDS
  }

  depends_on = [helm_release.crossplane]
}

resource "kubectl_manifest" "aws_provider_config" {
  count      = var.enable_aws_provider_config ? 1 : 0
  depends_on = [kubernetes_secret.aws_creds, kubectl_manifest.provider_aws_ecr]

  yaml_body = <<-YAML
    apiVersion: aws.upbound.io/v1beta1
    kind: ProviderConfig
    metadata:
      name: default
    spec:
      credentials:
        source: Secret
        secretRef:
          namespace: crossplane-system
          name: aws-creds
          key: creds
  YAML
}
