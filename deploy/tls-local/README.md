# Local TLS for minikube (cert-manager + self-signed CA)

Issues HTTPS certificates for the Backstage and ArgoCD hostnames on the local
minikube cluster.

**This stack is local-only.** It talks to minikube through the `kubernetes`,
`helm`, and `kubectl` providers and creates nothing in AWS. State stays on
disk and is gitignored — destroy and recreate it freely.

## Quick start

```bash
# one-time prerequisites
minikube addons enable ingress
helm repo add jetstack https://charts.jetstack.io && helm repo update

cd deploy/tls-local
terraform init
terraform apply

# leave this running — it is what makes the URLs reachable
kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 8443:443
```

Then browse:

| | URL |
| --- | --- |
| Backstage | <https://backstage.127.0.0.1.nip.io:8443> |
| ArgoCD | <https://argocd.127.0.0.1.nip.io:8443> |

Expect a certificate warning until you import the CA (below). Click through it
in the meantime.

## No Administrator required — and why that shaped the design

Two obvious approaches both need elevation on Windows, so neither is used:

- **Editing the hosts file** to map `*.dev.local` — needs Administrator.
- **`minikube tunnel`** — binds ports 80/443, needs Administrator, and must
  stay running.

Instead:

- **Hostnames use `nip.io`**, public wildcard DNS where
  `<anything>.127.0.0.1.nip.io` resolves to `127.0.0.1`. No hosts file.
- **The ingress is port-forwarded to 8443**, a high port any user can bind.

The trade-off is that `nip.io` is a third-party DNS service, so this needs
working internet DNS. If you would rather be fully offline, set
`backstage_host`/`argocd_host` to `*.dev.local`, add hosts entries as
Administrator, and the rest works the same.

## Why not ACM?

An AWS ACM certificate needs a registered domain in a Route53 hosted zone for
DNS validation, and only does anything when TLS terminates at an ALB or
CloudFront. There is no domain, no hosted zone, and no EKS cluster here — so
ACM would fail validation and produce a certificate nothing could use.
cert-manager with a local CA is the right tool for a local cluster.

The trade-off: the CA is self-signed, so browsers warn until you import it.
These certificates are not publicly trusted — fine locally, unacceptable for
anything real.

## What it creates

| Resource | Purpose |
| --- | --- |
| `helm_release.cert_manager` | cert-manager, with CRDs |
| ClusterIssuer `selfsigned-bootstrap` | Bootstraps the root only |
| Certificate `local-ca-root` (cert-manager ns) | The root CA — 10 year lifetime |
| ClusterIssuer `local-ca` | Signs leaf certs from that root |
| Certificate `backstage-tls` (backstage-dev ns) | Leaf for the Backstage host, 90 day |
| Certificate `argocd-tls` (argocd ns) | Leaf for the ArgoCD host, 90 day |
| Ingress `argocd-server` (argocd ns) | Serves the ArgoCD UI over HTTPS |

Two issuers exist because a self-signed issuer cannot sign for other names.
The bootstrap issuer signs one thing — the root CA — and the CA issuer then
signs every leaf. Importing that one root makes all leaves trusted.

Backstage's Ingress is **not** created here; it comes from the Helm chart,
whose `values-dev.yaml` references `secretName: backstage-tls`, the secret
this stack produces.

## Trusting the CA (removes the browser warning)

```bash
kubectl get secret local-ca-root -n cert-manager \
  -o jsonpath='{.data.tls\.crt}' | base64 -d > local-ca.crt
```

Then, as Administrator:

```powershell
Import-Certificate -FilePath local-ca.crt -CertStoreLocation Cert:\LocalMachine\Root
```

Restart the browser. Firefox keeps its own store — import there separately.

`local-ca.crt` is gitignored. It is only a public certificate, but the matching
private key lives in the `local-ca-root` secret in the cluster, and anyone
holding it can mint certificates your machine trusts. Do not reuse this CA
outside local development.

## Verifying

From the host:

```bash
curl -sk -o /dev/null -w '%{http_code}\n' https://backstage.127.0.0.1.nip.io:8443/
```

Or independent of the port-forward, from inside the cluster:

```bash
IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.spec.clusterIP}')
kubectl run tls-test --rm -i --restart=Never --image=curlimages/curl:latest -- \
  curl -skv --resolve backstage.127.0.0.1.nip.io:443:$IP https://backstage.127.0.0.1.nip.io/
```

Expect `HTTP 200` and `issuer: CN=EDX-BACKTAGE Local Dev CA`.

Issuance status:

```bash
kubectl get certificate -A     # READY True for all three
kubectl get clusterissuer      # both True
```

## Troubleshooting

**`503 Service Temporarily Unavailable`** — nginx has no healthy backend.
Check the Service actually has endpoints:

```bash
kubectl get endpoints backstage -n backstage-dev
```

If empty, the Service selector does not match any pod. This happens when the
Deployment and Service come from different chart versions — the app tier
selects on `app.kubernetes.io/component: backstage`, and a Deployment rendered
before that label existed produces pods without it. The Deployment selector is
immutable, so fixing it means deleting and recreating the Deployment.

**Backstage loads but every API call 401s** — `APP_BASE_URL`/`BACKEND_BASE_URL`
in `values-dev.yaml` must match exactly how the browser reaches the portal,
**including the `:8443` port**. The frontend uses them verbatim; without the
port it calls `:443` and every request fails.

**`no cached repo found` on apply** — the Helm provider reads the local repo
cache. Run `helm repo add jetstack https://charts.jetstack.io && helm repo update`.

**Certificate stuck `READY=False`** — describe it; cert-manager records the
reason on the resource and on its CertificateRequest child.

## Renewal

Leaf certs last 90 days and cert-manager renews them 15 days before expiry
with no intervention. The root CA lasts 10 years; when it is replaced every
leaf is reissued and the new root must be imported again.
