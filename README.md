# EDX-BACKTAGE

A [Red Hat Developer Hub](https://developers.redhat.com/products/rhdh) portal and
the platform that delivers it: Helm → ArgoCD, with Terraform for the AWS side.

RHDH is Red Hat's build of [Backstage](https://backstage.io), the CNCF
developer-portal platform originally built by Spotify. It gives an engineering
org one front door: a **Software Catalog** of every service and who owns it,
**Software Templates** for golden-path scaffolding, and **TechDocs** for docs
that live beside the code.

**This repository builds no application.** RHDH ships as a prebuilt container
image that Red Hat maintains; everything here is configuration, catalog content
and delivery machinery. There is no `packages/`, no `Dockerfile`, no
`yarn install` — customisation happens through app-config and *dynamic plugins*
declared in the Helm values.

## The platform loop

```
                         Developer
                             │
                             ▼
                     ┌───────────────┐
                     │      RHDH     │
                     │Platform Portal│
                     └───────────────┘
                       │     │     │
             ┌─────────┘     │     └─────────┐
             ▼               ▼               ▼
       Software           Catalog         TechDocs
       Templates
             │
             ▼
       GitHub Repository       (scaffolder creates it)
             │
             ▼
       GitHub Actions (CI)     (tests, builds, pushes to ECR)
             │
             ▼
       GitOps Ledger           gitops/services/<svc>/<env>/config.yaml
             │
             ▼
       Argo CD                 `services` ApplicationSet reads the ledger
             │
             ▼
       Kubernetes
             │
             ▼
       Crossplane              ServiceRegistry / ObjectStore claims
             │
             ▼
       AWS resources
```

The only hand-off in that chain is code review. The scaffolder creates a repo
and never touches the cluster; the cluster changes because a commit landed in
the ledger. See [gitops/README.md](gitops/README.md) for the ledger contract and
[deploy/argocd/README.md](deploy/argocd/README.md) for how to bootstrap it.

One stage is narrower than the diagram suggests: Crossplane ships an Azure
provider but no Azure Composition, so "cloud resources" means AWS in practice.

## The platform loop

```
                         Developer
                             │
                             ▼
                     ┌───────────────┐
                     │   Backstage   │
                     │ Platform Portal│
                     └───────────────┘
                       │     │     │
             ┌─────────┘     │     └─────────┐
             ▼               ▼               ▼
       Software           Catalog         TechDocs
       Templates
             │
             ▼
       GitHub Repository       (scaffolder creates it)
             │
             ▼
       GitHub Actions (CI)     (tests, builds, pushes to ECR)
             │
             ▼
       GitOps Ledger           gitops/services/<svc>/<env>/config.yaml
             │
             ▼
       Argo CD                 `services` ApplicationSet reads the ledger
             │
             ▼
       Kubernetes
             │
             ▼
       Crossplane              ServiceRegistry / ObjectStore claims
             │
             ▼
       AWS resources
```

The only hand-off in that chain is code review. The scaffolder creates a repo
and never touches the cluster; the cluster changes because a commit landed in
the ledger. See [gitops/README.md](gitops/README.md) for the ledger contract and
[deploy/argocd/README.md](deploy/argocd/README.md) for how to bootstrap it.

Two stages are narrower than the diagram suggests: TechDocs is configured for
local builds and does not work in-cluster yet, and Crossplane ships an Azure
provider but no Azure Composition, so "cloud resources" means AWS in practice.

## Layout

```
packages/
  app/                    # React frontend
  backend/                # Node backend (plugins, catalog, scaffolder)
examples/                 # sample catalog entities, org, and a template
plugins/                  # your own plugins go here
templates/                # golden-path scaffolder template
gitops/                   # deployment ledger — what runs where, at which version
app-config.yaml           # base config (local dev defaults)
app-config.production.yaml# production overrides; reads ${POSTGRES_*} etc.
catalog-info.yaml         # this repo's own catalog entry
docs/ + mkdocs.yml        # TechDocs source for this repo
deploy/
  helm/backstage/         # Helm chart
  argocd/                 # ArgoCD AppProjects, Applications, ApplicationSet
  crossplane/             # Crossplane install, XRDs, Compositions
  runners/                # self-hosted GitHub Actions runners (see its README)
terraform/                # ECR, GitHub OIDC roles, remote state
```

## Prerequisites

No Node, no Yarn, no Unix-only build. What you need is a cluster and:

- `helm` 3.16+
- `kubectl`
- a Kubernetes 1.27+ cluster (minikube/kind for dev)
- a GitHub OAuth app — sign-in is GitHub-only and the backend will not start
  without it

Windows is fine now: nothing here compiles.

## Quick start (local cluster)

```bash
# 1. TLS for the local hostname — see deploy/tls-local/README.md
# 2. Credentials. There is no guest sign-in.
kubectl create namespace rhdh-dev
kubectl -n rhdh-dev create secret generic rhdh-dev-secrets \
  --from-literal=AUTH_GITHUB_CLIENT_ID=... \
  --from-literal=AUTH_GITHUB_CLIENT_SECRET=... \
  --from-literal=GITHUB_TOKEN=...

# 3. Install
helm dependency build deploy/helm/rhdh
helm upgrade --install rhdh deploy/helm/rhdh \
  --namespace rhdh-dev \
  -f deploy/helm/rhdh/values.yaml \
  -f deploy/helm/rhdh/values-dev.yaml
```

Portal → <https://backstage.127.0.0.1.nip.io:8443>

The GitHub OAuth app's callback URL must be
`https://backstage.127.0.0.1.nip.io:8443/api/auth/github/handler/frame`, and your
GitHub login must match a `User` entity in the catalog — `examples/org.yaml`
carries placeholders for exactly that reason.

First boot is slow. Before the backend starts, an `install-dynamic-plugins` init
container downloads and unpacks every enabled plugin. Watch that container, not
the main one, when a pod looks stuck:

```bash
kubectl -n rhdh-dev logs -l app.kubernetes.io/instance=rhdh -c install-dynamic-plugins -f
```

## Configuration

Everything lives in [deploy/helm/rhdh](deploy/helm/rhdh) — that directory's
[README](deploy/helm/rhdh/README.md) is the reference. In short:

| Where | What |
| --- | --- |
| `values.yaml` → `backstage.upstream.backstage.appConfig` | the Backstage app-config, rendered into a ConfigMap |
| `values.yaml` → `global.dynamic.plugins` | which plugins are on — this replaces the old `packages/backend/src/index.ts` |
| `values-<env>.yaml` | hostname, ingress, database, replicas, which Secret to read |

Secrets are never created by the chart. Required keys per environment:

| Key | Purpose |
| --- | --- |
| `AUTH_GITHUB_CLIENT_ID` / `AUTH_GITHUB_CLIENT_SECRET` | GitHub OAuth app — sign-in fails to start without them |
| `GITHUB_TOKEN` | optional; PAT for catalog ingestion and the scaffolder |
| `postgres-password` | database password (staging/prod) |
| `backend-secret` | backend-to-backend auth; `openssl rand -base64 32` (staging/prod) |

### Adding things to the catalog

Add a `catalog-info.yaml` to the repo in question, then add a target to
[catalog/all.yaml](catalog/all.yaml). That file is a `Location` entity whose
targets resolve relative to itself, which is why app-config names exactly one
location and why repointing an environment at a different branch is a one-line
change.

Nothing in this repository is inside the container image any more, so the old
`type: file` locations are gone — every entity is fetched over HTTP through the
GitHub integration.

## Kubernetes deploy (Helm + ArgoCD)

Chart at `deploy/helm/rhdh`, ArgoCD manifests at `deploy/argocd`.

```bash
helm dependency build deploy/helm/rhdh

helm template rhdh deploy/helm/rhdh \
  -f deploy/helm/rhdh/values.yaml \
  -f deploy/helm/rhdh/values-dev.yaml
```

The chart renders a Deployment (probes on
`/.backstage/health/v1/{liveness,readiness}`, non-root, read-only root
filesystem), a Service on **7007**, an Ingress, an optional in-cluster Postgres
StatefulSet for dev, and optional HPA/PDB.

There is **no migration Job** — Backstage runs its own Knex migrations at
startup.

Database selection:

- dev → `backstage.upstream.postgresql.enabled: true`, in-cluster StatefulSet
- staging/prod → subchart off, RDS endpoint in
  `appConfig.backend.database.connection.host`

`deploy/helm/rhdh/templates/validate.yaml` fails the render if neither is set,
rather than deploying something that cannot reach a database.

### ArgoCD

```bash
kubectl apply -f deploy/argocd/project.yaml
kubectl apply -f deploy/argocd/application-dev.yaml
```

Applications use `automated: { prune: true, selfHeal: true }` and
`ServerSideApply=true`. The RHDH chart is a Helm dependency, so ArgoCD needs
egress to `redhat-developer.github.io` and `charts.bitnami.com`; both are on the
AppProject's `sourceRepos` allow-list. See
[deploy/argocd/README.md](deploy/argocd/README.md).

## Upgrading RHDH

There is no build to promote — every environment runs the same Red Hat image, and
upgrading is an edit to three fields that must move together (CI enforces it):

- `deploy/helm/rhdh/Chart.yaml` → `appVersion`
- `deploy/helm/rhdh/values.yaml` → `backstage.upstream.backstage.image.tag`
- `deploy/helm/rhdh/values.yaml` → `global.catalogIndex.image.tag`

Details, including how to re-pin the chart itself, are in the
[chart README](deploy/helm/rhdh/README.md).

## Infrastructure (Terraform)

`terraform/` provisions:

- **ECR repository** — `IMMUTABLE` tags, `scan_on_push`, AES256, lifecycle policy
- **GitHub OIDC roles** — an image-push role scoped by `sub` claim; plus separate
  Terraform `plan` (read-only, PRs) and `apply` (read/write, `main` only) roles.
  No long-lived AWS keys in GitHub.
- **Remote state** — S3 with versioning, encryption, and native S3 locking

State lives in S3, and plan/apply run in GitHub Actions. Local runs are only for
bootstrapping. See `terraform/README.md`.

## CI / CD (GitHub Actions)

| Workflow | Trigger | Does |
| --- | --- | --- |
| `ci.yml` | PR + push to `main` | `helm dependency build` → `helm lint` → `helm template` for all three environments → image/appVersion pin check → catalog entities parse and every `catalog/all.yaml` target resolves |
| `security.yml` | PR + push + weekly cron | Trivy fs, Trivy config (rendered Helm + IaC), Gitleaks — all to the **Security** tab as SARIF |
| `terraform.yml` | PR/push touching `terraform/**` | `plan` on PRs (read-only role, posts the plan as a comment); `apply` on `main` |

`cd-dev.yml`, `promote.yml` and `release.yml` are gone with the image build.

### Required repo variables

Settings → Secrets and variables → Actions → **Variables**:

| Variable | Value |
| --- | --- |
| `AWS_REGION` | `us-east-1` |
| `TF_PLAN_ROLE_ARN` | `terraform output -raw terraform_plan_role_arn` |
| `TF_APPLY_ROLE_ARN` | `terraform output -raw terraform_apply_role_arn` |

### Scanning gates

| Scan | Blocks on |
| --- | --- |
| Trivy fs | CRITICAL |
| Trivy config (rendered Helm + IaC) | HIGH+ misconfig |
| Gitleaks | any leak |

CodeQL and `yarn audit` went with the application source. The RHDH image is Red
Hat's to patch, so it is not scanned here — the lever is the pinned tag, not a
gate that nobody in this repo could clear.

Suppress false positives in `.trivyignore` or `.gitleaks.toml`, with a comment
explaining why.

## Known gaps

Things that are deliberately unfinished — read before deploying:

- **No RDS in Terraform.** Staging and prod expect an endpoint in
  `appConfig.backend.database.connection.host`, but nothing provisions that
  database yet, and both values files ship with it blank so the chart refuses to
  render. The in-cluster Postgres is a single pod with no backups — dev only.
- **The ECR repository in `terraform/` is now orphaned.** It existed to hold this
  repo's own image, and there is no longer one. Scaffolded services get their
  registries from the Crossplane `ServiceRegistry` claim instead. It is left in
  place rather than destroyed; delete it once you have confirmed nothing else
  pulls from it.
- **`example.com` placeholders** in `values-staging.yaml` and `values-prod.yaml`,
  along with the `EDX Developer Hub` / `EDX Platform` branding in `values.yaml`.
- **Org data is hand-written.** `examples/org.yaml` carries placeholder `User`
  entities because GitHub sign-in resolves against the catalog and there is no
  GitHub *organisation* to ingest from. Enabling `GithubOrgEntityProvider` — the
  dynamic plugin is present but disabled — is what retires that file.
- **Two capabilities did not survive the migration.** RHDH 1.10 has no dynamic
  plugin for `@backstage/plugin-mcp-actions-backend` (the MCP actions endpoint
  and its `mcpActions` config), and no `scaffolder-backend-module-notifications`,
  so the `notification:send` step in `examples/template/template.yaml` has been
  removed. Both would need a custom dynamic plugin built and published to an OCI
  registry.
