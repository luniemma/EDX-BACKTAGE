########################################
# Xeta AI Platform APIs
########################################
# Makes the ObjectStore API from luniemma/xeta-ai-platform usable on this
# cluster. Its Compositions could not be applied as-is — they use
# `mode: Resources`, which Crossplane 2.x rejects — so a migrated Pipeline-mode
# copy lives in ./xeta. See that file's header for the details.
#
# Installing the API costs nothing. Creating an ObjectStore claim provisions a
# real S3 bucket, which does cost — the claim is deliberately not applied here.

resource "kubectl_manifest" "provider_aws_s3" {
  count      = var.install_xeta_apis ? 1 : 0
  depends_on = [helm_release.crossplane]

  # Must track the same release train as provider-family-aws; mixing a v1
  # service provider with a v2 family conflicts on the shared ProviderConfig
  # CRD. The upstream repo pins v1.10.0, which is why it cannot simply be
  # pointed at this cluster.
  yaml_body = <<-YAML
    apiVersion: pkg.crossplane.io/v1
    kind: Provider
    metadata:
      name: provider-aws-s3
    spec:
      package: xpkg.upbound.io/upbound/provider-aws-s3:v2.6.2
  YAML
}

resource "kubectl_manifest" "xeta_xrd_objectstore" {
  count      = var.install_xeta_apis ? 1 : 0
  depends_on = [helm_release.crossplane]
  yaml_body  = file("${path.module}/xeta/xrd-objectstore.yaml")
}

resource "kubectl_manifest" "xeta_composition_objectstore" {
  count = var.install_xeta_apis ? 1 : 0
  depends_on = [
    kubectl_manifest.xeta_xrd_objectstore,
    kubectl_manifest.function_patch_and_transform,
    kubectl_manifest.provider_aws_s3,
  ]
  yaml_body = file("${path.module}/xeta/composition-objectstore.yaml")
}
