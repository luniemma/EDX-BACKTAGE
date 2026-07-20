# EDX-BACKTAGE

A [Backstage](https://backstage.io) developer portal, with the delivery pipeline
to ship it: container build → ECR → Helm → ArgoCD, and Terraform for the AWS
side.

Backstage is the CNCF developer-portal platform originally built by Spotify. It
gives an engineering org one front door: a **Software Catalog** of every service
and who owns it, **Software Templates** for golden-path scaffolding, and
**TechDocs** for docs that live beside the code.

## Layout

```
packages/
  app/                    # React frontend
  backend/                # Node backend (plugins, catalog, scaffolder)
examples/                 # sample catalog entities, org, and a template
plugins/                  # your own plugins go here
app-config.yaml           # base config (local dev defaults)
app-config.production.yaml# production overrides; reads ${POSTGRES_*} etc.
catalog-info.yaml         # this repo's own catalog entry
Dockerfile                # multi-stage build for the backend
deploy/
  helm/backstage/         # Helm chart
  argocd/                 # ArgoCD AppProject + Applications
terraform/                # ECR, GitHub OIDC roles, remote state
```

## Prerequisites

Backstage requires a **Unix-like OS** — Linux, macOS, or **WSL** on Windows.
It does not build natively on Windows: the scaffolder's `isolated-vm` dependency
needs a GNU toolchain.

- Node **22 or 24** (`nvm install 22`)
- Yarn **4.x** via corepack (`corepack enable`)
- Docker (for a local Postgres, and to build the image)
- ~20 GB free disk — `node_modules` alone is ~1.8 GB

> **Windows users:** clone into the WSL filesystem (`~/EDX-BACKTAGE`), not a
> Windows path under `/mnt/c`. A OneDrive-synced folder is especially bad — it
> will try to sync 1.8 GB of `node_modules`.

## Quick start

```bash
corepack enable
yarn install
yarn start
```

- Frontend → <http://localhost:3000>
- Backend  → <http://localhost:7007>

Out of the box this uses an in-memory SQLite database and the `guest` auth
provider, so there is nothing else to configure. Both are development-only.

### Useful scripts

| Script | Purpose |
| --- | --- |
| `yarn start` | Run frontend + backend with hot reload |
| `yarn tsc` | Typecheck |
| `yarn lint:all` | Lint every workspace |
| `yarn test:all` | Run tests with coverage |
| `yarn build:backend` | Build the backend bundle |
| `yarn build-image` | Build the image via Backstage's own Dockerfile |
| `yarn new` | Scaffold a new plugin |

## Configuration

`app-config.yaml` holds local defaults; `app-config.production.yaml` layers on
top in the container and reads everything from the environment:

| Variable | Purpose |
| --- | --- |
| `POSTGRES_HOST` / `POSTGRES_PORT` | Database endpoint |
| `POSTGRES_USER` / `POSTGRES_PASSWORD` | Database credentials |
| `APP_BASE_URL` / `BACKEND_BASE_URL` | Externally reachable URL — **not** localhost, the browser uses it |
| `GITHUB_TOKEN` | PAT for catalog ingestion and the scaffolder |
| `BACKEND_SECRET` | Shared secret for backend-to-backend auth |
| `NODE_OPTIONS=--no-node-snapshot` | Required for `isolated-vm` on Node 20+ |

The Helm chart supplies all of these — non-secret values via ConfigMap, the rest
via Secret.

### Adding things to the catalog

Register a component by adding a `catalog-info.yaml` to its repo, then point
`catalog.locations` in `app-config.production.yaml` at it (or register it through
the UI). This repo ships its own `catalog-info.yaml` as an example.

## Docker

The root `Dockerfile` is a **self-contained multi-stage build**, so CI can run a
plain `docker build .` with no host preparation:

```bash
docker build -t backstage .
```

Backstage also ships a host-build variant at `packages/backend/Dockerfile`, which
expects `yarn build:backend` to have run first. The root one is what CI uses.

Both compile `isolated-vm` and `better-sqlite3` from source, which is why the
image installs `python3`, `g++`, `build-essential`, and `libsqlite3-dev`.

## Kubernetes deploy (Helm + ArgoCD)

Chart at `deploy/helm/backstage`, ArgoCD manifests at `deploy/argocd`.

```bash
# render locally
helm template backstage deploy/helm/backstage \
  -f deploy/helm/backstage/values.yaml \
  -f deploy/helm/backstage/values-dev.yaml

# install
helm upgrade --install backstage deploy/helm/backstage \
  --namespace backstage-dev --create-namespace \
  -f deploy/helm/backstage/values-dev.yaml
```

The chart provisions a Deployment (probes on
`/.backstage/health/v1/{liveness,readiness}`, non-root, envFrom ConfigMap +
Secret), a Service on **7007**, an optional Ingress, an optional in-cluster
Postgres StatefulSet for dev, and optional HPA/PDB/ServiceAccount.

There is **no migration Job** — Backstage runs its own Knex migrations at
startup.

Database selection:

- `postgres.enabled: true` → in-cluster StatefulSet (**dev only**)
- `externalPostgres.host: <rds-endpoint>` → managed Postgres (staging/prod)

The chart fails to render if neither is set, rather than deploying something
that cannot reach a database.

### ArgoCD

```bash
kubectl apply -f deploy/argocd/project.yaml
kubectl apply -f deploy/argocd/application-dev.yaml
```

Applications use `automated: { prune: true, selfHeal: true }` and
`ServerSideApply=true`. Staging and prod set `secrets.existingSecret`, so
credentials come from External Secrets / Sealed Secrets / Vault — never Git.
See `deploy/argocd/README.md`.

## Infrastructure (Terraform)

`terraform/` provisions:

- **ECR repository** — `IMMUTABLE` tags, `scan_on_push`, AES256, lifecycle policy
  (expire untagged after 7d; keep last 30 `v*` and 50 `sha-*`)
- **GitHub OIDC roles** — an image-push role scoped by `sub` claim to `main`,
  `release/*` and `v*.*.*`; plus separate Terraform `plan` (read-only, PRs) and
  `apply` (read/write, `main` only) roles. No long-lived AWS keys in GitHub.
- **Remote state** — S3 with versioning, encryption, and native S3 locking

State lives in S3, and plan/apply run in GitHub Actions. Local runs are only for
bootstrapping. See `terraform/README.md`.

## CI / CD (GitHub Actions)

| Workflow | Trigger | Does |
| --- | --- | --- |
| `ci.yml` | PR + push to `main` | `yarn install --immutable` → `tsc` → lint → test → `helm lint`/`template` → docker build (PR only, no push) |
| `security.yml` | PR + push + weekly cron | CodeQL, `yarn npm audit`, Trivy fs, Trivy config (rendered Helm), Gitleaks — all to the **Security** tab as SARIF |
| `cd-dev.yml` | push to `main` (app paths) | OIDC → build + push image to ECR as `sha-<short>` → Trivy image scan (fails on CRITICAL) → bump `values-dev.yaml` and commit back |
| `terraform.yml` | PR/push touching `terraform/**` | `plan` on PRs (read-only role, posts the plan as a comment); `apply` on `main` |
| `release.yml` | tag `v*.*.*` | Build + push a semver-tagged image, open a PR against `release/prod` |
| `promote.yml` | manual | Promote an existing image between environments, gated by GitHub Environment approvals |

The image is **never rebuilt** during promotion — the digest that soaked in dev
is what reaches prod.

### Required repo variables

Settings → Secrets and variables → Actions → **Variables** (not Secrets — none of
these are sensitive):

| Variable | Value |
| --- | --- |
| `AWS_REGION` | `us-east-1` |
| `ECR_REGISTRY` | `<account>.dkr.ecr.<region>.amazonaws.com` |
| `ECR_REPOSITORY` | `backend-api` |
| `AWS_ROLE_TO_ASSUME` | `terraform output -raw github_push_role_arn` |
| `TF_PLAN_ROLE_ARN` | `terraform output -raw terraform_plan_role_arn` |
| `TF_APPLY_ROLE_ARN` | `terraform output -raw terraform_apply_role_arn` |

### Scanning gates

| Scan | Blocks on |
| --- | --- |
| CodeQL (`security-and-quality`) | high-severity JS/TS alerts |
| `yarn npm audit --environment production` | HIGH+ in prod deps (full tree is informational) |
| Trivy fs | CRITICAL |
| Trivy config (Dockerfile + rendered Helm) | HIGH+ misconfig |
| Trivy image (`cd-dev.yml`) | CRITICAL — blocks the values bump, so a vulnerable image never reaches ArgoCD |
| Gitleaks | any leak |

Suppress false positives in `.trivyignore` or `.gitleaks.toml`, with a comment
explaining why.

## Known gaps

Things that are deliberately unfinished — read before deploying:

- **The ECR repository is still named `backend-api`.** This repo previously held
  an Express notes API; renaming the ECR repo means destroying and recreating it,
  so it was left alone. The chart's `image.repository` points at it.
- **No RDS in Terraform.** Staging and prod values expect
  `externalPostgres.host`, but nothing provisions that database yet. The
  in-cluster Postgres is a single pod with no backups — dev only.
- **Auth is `guest`.** `app-config.production.yaml` ships the guest provider.
  Wire up a real identity provider (GitHub, OIDC) before exposing this.
- **`app.baseUrl` / `backend.baseUrl` are `example.com` placeholders** in the
  values files.
- **amd64 only.** `cd-dev.yml` builds a single architecture; compiling
  `isolated-vm` for arm64 under QEMU is too slow for CI. Use native arm runners
  if you need it.
