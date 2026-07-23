########################################
# Platform API: ServiceRegistry
########################################
# An XRD defines the API a developer sees; the Composition defines what that
# actually provisions. This one is deliberately small and cheap: a developer
# asks for "a container registry for my service" and gets an ECR repository,
# without needing to know ECR exists.
#
# ECR costs storage only (no hourly charge), which makes it a safe first
# Composition. Do not extend this to RDS/EKS without a cost conversation.

resource "kubectl_manifest" "xrd_service_registry" {
  depends_on = [helm_release.crossplane]

  yaml_body = <<-YAML
    apiVersion: apiextensions.crossplane.io/v1
    kind: CompositeResourceDefinition
    metadata:
      name: xserviceregistries.platform.edx-backtage.io
    spec:
      group: platform.edx-backtage.io
      names:
        kind: XServiceRegistry
        plural: xserviceregistries
      claimNames:
        kind: ServiceRegistry
        plural: serviceregistries
      versions:
        - name: v1alpha1
          served: true
          referenceable: true
          schema:
            openAPIV3Schema:
              type: object
              properties:
                spec:
                  type: object
                  properties:
                    serviceName:
                      type: string
                      description: Name of the service; becomes the registry name.
                      pattern: '^[a-z][a-z0-9-]{1,60}$'
                    immutableTags:
                      type: boolean
                      description: Reject overwriting an existing image tag.
                      default: true
                    scanOnPush:
                      type: boolean
                      description: Scan images for vulnerabilities on push.
                      default: true
                  required:
                    - serviceName
                status:
                  type: object
                  properties:
                    repositoryUrl:
                      type: string
  YAML
}

resource "kubectl_manifest" "composition_service_registry" {
  depends_on = [kubectl_manifest.xrd_service_registry]

  yaml_body = <<-YAML
    apiVersion: apiextensions.crossplane.io/v1
    kind: Composition
    metadata:
      name: serviceregistry-aws-ecr
    spec:
      compositeTypeRef:
        apiVersion: platform.edx-backtage.io/v1alpha1
        kind: XServiceRegistry
      mode: Pipeline
      pipeline:
        - step: patch-and-transform
          functionRef:
            name: function-patch-and-transform
          input:
            apiVersion: pt.fn.crossplane.io/v1beta1
            kind: Resources
            resources:
              - name: ecr-repository
                base:
                  apiVersion: ecr.aws.upbound.io/v1beta1
                  kind: Repository
                  spec:
                    forProvider:
                      region: ${var.aws_region}
                      imageTagMutability: IMMUTABLE
                      imageScanningConfiguration:
                        - scanOnPush: true
                      encryptionConfiguration:
                        - encryptionType: AES256
                patches:
                  - type: FromCompositeFieldPath
                    fromFieldPath: spec.serviceName
                    toFieldPath: metadata.annotations[crossplane.io/external-name]
                  - type: FromCompositeFieldPath
                    fromFieldPath: spec.immutableTags
                    toFieldPath: spec.forProvider.imageTagMutability
                    transforms:
                      - type: map
                        map:
                          "true": IMMUTABLE
                          "false": MUTABLE
                  - type: FromCompositeFieldPath
                    fromFieldPath: spec.scanOnPush
                    toFieldPath: spec.forProvider.imageScanningConfiguration[0].scanOnPush
                  - type: ToCompositeFieldPath
                    fromFieldPath: status.atProvider.repositoryUrl
                    toFieldPath: status.repositoryUrl
  YAML
}

# Pipeline-mode Compositions need this function installed.
resource "kubectl_manifest" "function_patch_and_transform" {
  depends_on = [helm_release.crossplane]

  yaml_body = <<-YAML
    apiVersion: pkg.crossplane.io/v1
    kind: Function
    metadata:
      name: function-patch-and-transform
    spec:
      package: xpkg.upbound.io/crossplane-contrib/function-patch-and-transform:v0.7.0
  YAML
}
