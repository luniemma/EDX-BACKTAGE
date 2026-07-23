########################################
# Safety guard
########################################
# Refuse to run against anything but the local minikube cluster. The providers
# are already pinned to var.kube_context, but this makes a misconfiguration
# fail loudly at plan instead of touching a real cluster.
data "kubernetes_nodes" "this" {}

check "is_minikube" {
  assert {
    condition     = contains([for n in data.kubernetes_nodes.this.nodes : n.metadata[0].name], "minikube")
    error_message = "This stack is local-only; the target cluster does not look like minikube."
  }
}

########################################
# cert-manager
########################################
resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = var.cert_manager_version
  namespace        = "cert-manager"
  create_namespace = true

  set {
    name  = "crds.enabled"
    value = "true"
  }
}

########################################
# Self-signed local CA
########################################
# 1) A SelfSigned issuer just to bootstrap the root.
resource "kubectl_manifest" "selfsigned_issuer" {
  depends_on = [helm_release.cert_manager]
  yaml_body  = <<-YAML
    apiVersion: cert-manager.io/v1
    kind: ClusterIssuer
    metadata:
      name: selfsigned-bootstrap
    spec:
      selfSigned: {}
  YAML
}

# 2) The root CA certificate, signed by the bootstrap issuer. Its keypair lands
#    in secret local-ca-root in the cert-manager namespace. This is the cert
#    you import into your OS/browser trust store — see README.
resource "kubectl_manifest" "ca_certificate" {
  depends_on = [kubectl_manifest.selfsigned_issuer]
  yaml_body  = <<-YAML
    apiVersion: cert-manager.io/v1
    kind: Certificate
    metadata:
      name: local-ca-root
      namespace: cert-manager
    spec:
      isCA: true
      commonName: EDX-BACKTAGE Local Dev CA
      secretName: local-ca-root
      duration: 87600h   # 10 years — it's a local dev CA
      privateKey:
        algorithm: ECDSA
        size: 256
      issuerRef:
        name: selfsigned-bootstrap
        kind: ClusterIssuer
        group: cert-manager.io
  YAML
}

# 3) A CA issuer that signs leaf certs using that root.
resource "kubectl_manifest" "ca_issuer" {
  depends_on = [kubectl_manifest.ca_certificate]
  yaml_body  = <<-YAML
    apiVersion: cert-manager.io/v1
    kind: ClusterIssuer
    metadata:
      name: local-ca
    spec:
      ca:
        secretName: local-ca-root
  YAML
}

########################################
# Leaf certificates
########################################
# Each leaf cert is written to a TLS secret in the app's namespace, which the
# app's Ingress references.
resource "kubectl_manifest" "backstage_cert" {
  depends_on = [kubectl_manifest.ca_issuer]
  yaml_body  = <<-YAML
    apiVersion: cert-manager.io/v1
    kind: Certificate
    metadata:
      name: backstage-tls
      namespace: ${var.backstage_namespace}
    spec:
      secretName: backstage-tls
      dnsNames:
        - ${var.backstage_host}
      duration: 2160h      # 90 days
      renewBefore: 360h    # 15 days
      issuerRef:
        name: local-ca
        kind: ClusterIssuer
        group: cert-manager.io
  YAML
}

resource "kubectl_manifest" "argocd_cert" {
  depends_on = [kubectl_manifest.ca_issuer]
  yaml_body  = <<-YAML
    apiVersion: cert-manager.io/v1
    kind: Certificate
    metadata:
      name: argocd-tls
      namespace: ${var.argocd_namespace}
    spec:
      secretName: argocd-tls
      dnsNames:
        - ${var.argocd_host}
      duration: 2160h
      renewBefore: 360h
      issuerRef:
        name: local-ca
        kind: ClusterIssuer
        group: cert-manager.io
  YAML
}

########################################
# ArgoCD Ingress
########################################
# ArgoCD's server terminates TLS itself, so the ingress must speak HTTPS to the
# backend. The backend-protocol annotation switches nginx to HTTPS upstream,
# and ssl-passthrough is off so the leaf cert above is what the browser sees.
resource "kubectl_manifest" "argocd_ingress" {
  depends_on = [kubectl_manifest.argocd_cert]
  yaml_body  = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: Ingress
    metadata:
      name: argocd-server
      namespace: ${var.argocd_namespace}
      annotations:
        nginx.ingress.kubernetes.io/backend-protocol: HTTPS
    spec:
      ingressClassName: nginx
      tls:
        - hosts:
            - ${var.argocd_host}
          secretName: argocd-tls
      rules:
        - host: ${var.argocd_host}
          http:
            paths:
              - path: /
                pathType: Prefix
                backend:
                  service:
                    name: argocd-server
                    port:
                      number: 443
  YAML
}
