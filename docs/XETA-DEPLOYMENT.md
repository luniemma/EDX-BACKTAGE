# Running the Xeta AI Platform — what it actually takes

The Xeta AI Platform (`luniemma/xeta-ai-platform`, checked out under
`RTXsample/`) is cataloged in Backstage and its ObjectStore API is migrated
into this cluster's Crossplane. This document explains what a *real* deployment
of the platform would require — and why it does not, and largely cannot, run on
the local minikube setup or within a ~$50–100/month budget.

**Nothing here has been provisioned.** This is explanation only.

## What the platform is

```
Users ─HTTPS─▶ ALB ─▶ APIM SHG (EKS, public) ─mTLS─▶ LiteLLM (EKS, private) ─▶ Bedrock
                                                          │
                                    Redis (ElastiCache) ──┘   S3   Secrets Manager / KMS
```

A private LiteLLM proxy fronting Amazon Bedrock, gated by an Azure API
Management Self-Hosted Gateway, on EKS in an AWS Shared Services account.

## Why it will not run locally

Three hard blockers, read from the manifests — not assumptions:

1. **The LiteLLM image is a placeholder.**
   `artifactory.xeta.example.com/docker/litellm/litellm:v1.44.7-stable` — that
   registry does not exist. A local run would have to substitute the public
   `ghcr.io/berriai/litellm` image.

2. **Authentication is IRSA.** The LiteLLM ServiceAccount gets AWS credentials
   through IAM Roles for Service Accounts, an EKS-only mechanism. minikube has
   no IRSA, so as written the pod cannot authenticate to anything. A local run
   would have to replace it with a static-key Secret.

3. **The backend is Amazon Bedrock.** The model list is entirely
   `bedrock/anthropic.claude-*` and `bedrock/amazon.titan-*`. These require real
   AWS credentials and Bedrock model access enabled in the account. There is no
   local substitute for Bedrock itself.

The Azure APIM Self-Hosted Gateway in front is only the edge; its control plane
is a real Azure API Management instance, which is a paid Azure resource with no
local equivalent.

## What a real deployment provisions

The Terraform under `RTXsample/terraform/` stands up, per environment:

| Module | Creates |
| --- | --- |
| `vpc` | VPC, subnets, NAT gateways, interface endpoints |
| `eks` | EKS cluster + `system` and `apps` node groups |
| `elasticache` | Redis (`cache.r7g.large` in the NPD defaults) |
| `bedrock` | Bedrock access + guardrails |
| `kms`, `secrets` | KMS keys, Secrets Manager entries |
| `route53` | DNS |
| `irsa_*` | IRSA roles for ALB controller, autoscaler, external-dns, external-secrets, LiteLLM, Crossplane |
| `addons` | cluster add-ons |

Then GitOps (`kubernetes/`) deploys APIM SHG, LiteLLM, external-secrets,
observability, and ArgoCD itself.

## Rough cost

From the platform's own cost notes, the NPD environment "leans toward realism,
not minimum cost." The standing monthly drivers, before any Bedrock token spend:

| Driver | Order of magnitude |
| --- | --- |
| EKS control plane | ~$73 |
| EKS nodes (system + apps) | hundreds |
| NAT gateways (per-AZ) | ~$33 each |
| ElastiCache `cache.r7g.large` | hundreds |
| ALB + interface endpoints | tens–hundreds |
| Azure APIM instance | hundreds |
| Bedrock | per-token, on top |

Realistically **four figures a month** at the NPD defaults — one to two orders
of magnitude above the ~$50–100 ceiling set for this project, and it requires
an EKS cluster that does not exist here.

## What *could* run locally, if desired later

Not started — recorded so the option is clear:

- **LiteLLM on minikube** — swap to the public image, replace IRSA with a
  static-key Secret, point at real Bedrock. A working proxy; cost is Bedrock
  per-token (cents for testing). Needs an AWS key with Bedrock access.
- **The ObjectStore claim** (`crossplane/claims/objectstore-prompt-logs.yaml`)
  — wire AWS credentials into this cluster's Crossplane and apply it to create
  one real, encrypted, versioned S3 bucket. Pennies. This is infrastructure,
  not the application.

Both need real AWS credentials wired into the cluster and both incur real
(small) cost, which is why neither was done.

## What is already integrated

- **Backstage** — the platform is cataloged as a System with its components,
  API, and resources (`catalog/xeta-ai-platform/`).
- **Crossplane** — the ObjectStore API is migrated to Pipeline mode and live in
  this cluster (`deploy/crossplane/xeta/`). The API exists; no claim is applied,
  so no bucket is created.
