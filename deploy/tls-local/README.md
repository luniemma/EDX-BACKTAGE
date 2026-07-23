# Local TLS for minikube (cert-manager + self-signed CA)

Issues HTTPS certificates for the Backstage and ArgoCD hostnames on the local
minikube cluster.

**This stack is local-only.** It talks to minikube through the `kubernetes`,
`helm`, and `kubectl` providers and creates nothing in AWS. State stays on
disk and is gitignored — destroy and recreate it freely.

## Why not ACM?

An AWS ACM certificate needs a registered domain in a Route53 hosted zone for
DNS validation, and only does anything when TLS terminates at an ALB or
CloudFront. There is no domain, no hosted zone, and no EKS cluster here — so
ACM would fail validation and produce a certificate nothing could use.
cert-manager with a local CA is the right tool for a local cluster.

The trade-off: the CA is self-signed, so browsers show a trust warning until
you import it (see below). Certificates are not publicly trusted, which is
fine for local development and unacceptable for anything real.

## What it creates

| Resource | Purpose |
| --- | --- |
| `helm_release.cert_manager` | cert-manager, with CRDs |
| ClusterIssuer `selfsigned-bootstrap` | Bootstraps the root only |
| Certificate `local-ca-root` (cert-manager ns) | The root CA — 10 year lifetime |
| ClusterIssuer `local-ca` | Signs leaf certs from that root |
| Certificate `backstage-tls` (backstage-dev ns) | Leaf for `backstage.dev.local`, 90 day |
| Certificate `argocd-tls` (argocd ns) | Leaf for `argocd.dev.local`, 90 day |
| Ingress `argocd-server` (argocd ns) | Serves the ArgoCD UI over HTTPS |

Two issuers exist because a self-signed issuer cannot sign for other names.
The bootstrap issuer signs one thing — the root CA — and the CA issuer then
signs every leaf. Importing that one root makes all leaves trusted.

Backstage's Ingress is **not** created here; it comes from the Helm chart. The
chart's `values-dev.yaml` references `secretName: backstage-tls`, which is the
secret this stack produces.

## Prerequisites

- minikube running, with the ingress addon: `minikube addons enable ingress`
- `helm repo add jetstack https://charts.jetstack.io && helm repo update`
  (the Helm provider reads the local repo cache; without it the apply fails
  with `no cached repo found`)

## Apply

```bash
cd deploy/tls-local
terraform init
terraform apply
```

A `check` block asserts the target cluster is minikube, so a misconfigured
kubeconfig fails at plan rather than touching a real cluster.

## Reaching the URLs from Windows

Two things are needed, neither of which Terraform can do:

**1. Hosts file.** As Administrator, add to
`C:\Windows\System32\drivers\etc\hosts`:

```
127.0.0.1 backstage.dev.local
127.0.0.1 argocd.dev.local
```

**2. `minikube tunnel`.** With the docker driver the ingress is not reachable
on the minikube IP from Windows. Run this in a terminal and leave it open:

```bash
minikube tunnel
```

Then browse <https://backstage.dev.local> and <https://argocd.dev.local>.

## Trusting the CA (removes the browser warning)

Export the root:

```bash
kubectl get secret local-ca-root -n cert-manager \
  -o jsonpath='{.data.tls\.crt}' | base64 -d > local-ca.crt
```

Import it on Windows as Administrator:

```powershell
Import-Certificate -FilePath local-ca.crt `
  -CertStoreLocation Cert:\LocalMachine\Root
```

Restart the browser afterwards. Firefox keeps its own store — import there
separately if you use it.

`local-ca.crt` is gitignored. It is only a public certificate, not a key, but
the matching private key lives in the `local-ca-root` secret in the cluster —
anyone holding it can mint certificates your machine trusts. Do not reuse this
CA outside local development.

## Verifying

Independent of the hosts file and tunnel, from inside the cluster:

```bash
IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.spec.clusterIP}')
kubectl run tls-test --rm -i --restart=Never --image=curlimages/curl:latest -- \
  curl -skv --resolve backstage.dev.local:443:$IP https://backstage.dev.local/
```

Expect `HTTP 200` and `issuer: CN=EDX-BACKTAGE Local Dev CA`.

Check issuance status directly:

```bash
kubectl get certificate -A          # READY should be True for all three
kubectl get clusterissuer           # both should be True
```

If a certificate is stuck `READY=False`, describe it — cert-manager records
the reason on the resource and on its CertificateRequest child.

## Renewal

Leaf certs last 90 days and cert-manager renews them 15 days before expiry
with no intervention. The root CA lasts 10 years; when it is replaced every
leaf is reissued and the new root must be imported again.
