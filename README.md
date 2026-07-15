# backend-api

Full-featured Node.js backend: Express + TypeScript + Prisma (PostgreSQL) + JWT auth + Jest + Docker.

## Features

- **Auth**: register/login/me with JWT, bcrypt-hashed passwords, role-based access (`USER` / `ADMIN`)
- **DB**: PostgreSQL via Prisma with migrations and a seed script
- **Validation**: Zod schemas per module + global error handler
- **Security**: `helmet`, CORS, per-route rate limiting
- **Observability**: `pino` structured logs, request logs via `morgan`, `/health` endpoint
- **Tests**: Jest + Supertest, isolated test DB, DB-truncating `beforeEach`
- **Docker**: multi-stage Dockerfile + `docker-compose` (api + postgres) with healthchecks

## Project layout

```
src/
  config/env.ts           # Zod-validated environment
  db/client.ts            # Prisma singleton
  middleware/             # auth, validate, error, asyncHandler
  modules/
    auth/                 # register / login / me
    users/                # admin list + get by id
    notes/                # per-user CRUD
  utils/                  # jwt, password, logger, httpError
  app.ts                  # express app factory
  server.ts               # bootstrap + graceful shutdown
prisma/
  schema.prisma
  seed.ts
tests/
  auth.test.ts notes.test.ts health.test.ts
  globalSetup.ts globalTeardown.ts setup.ts
Dockerfile docker-compose.yml
```

## Quick start (Docker, recommended)

```bash
cp .env.example .env
docker compose up --build
# API on http://localhost:3000  |  Postgres on localhost:5432
```

Migrations run automatically on container start. To seed:

```bash
docker compose exec api npx tsx prisma/seed.ts
```

## Local development

Requires Node 20.19+ (22 LTS recommended) and a running Postgres.

```bash
cp .env.example .env
npm install
npm run prisma:generate
npm run prisma:migrate:dev    # first-time schema
npm run db:seed               # optional
npm run dev
```

## Tests

Tests need a Postgres instance. Point at a dedicated test DB:

```bash
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/appdb_test?schema=public \
JWT_SECRET=test-secret-that-is-long-enough-1234 \
npm test
```

Global setup applies migrations to that DB; each test truncates tables to stay isolated.

## API

Base URL: `http://localhost:3000`

### Health
```
GET  /health           -> 200 { status: "ok", uptime, timestamp }
```

### Auth
```
POST /api/auth/register  { email, password, name? }   -> 201 { user, token }
POST /api/auth/login     { email, password }          -> 200 { user, token }
GET  /api/auth/me        Authorization: Bearer <jwt>  -> 200 { user }
```

### Users (auth required)
```
GET  /api/users          ADMIN only                   -> 200 [User]
GET  /api/users/:id                                    -> 200 User
```

### Notes (auth required; each user only sees their own; ADMIN sees all)
```
GET    /api/notes                                     -> 200 [Note]
GET    /api/notes/:id                                 -> 200 Note
POST   /api/notes        { title, content }           -> 201 Note
PATCH  /api/notes/:id    { title?, content? }         -> 200 Note
DELETE /api/notes/:id                                 -> 204
```

### Example

```bash
# register
curl -s -X POST http://localhost:3000/api/auth/register \
  -H 'content-type: application/json' \
  -d '{"email":"me@example.com","password":"password123","name":"Me"}'

# save the token from the response, then:
TOKEN=...

curl -s -X POST http://localhost:3000/api/notes \
  -H "authorization: Bearer $TOKEN" -H 'content-type: application/json' \
  -d '{"title":"Hello","content":"world"}'

curl -s http://localhost:3000/api/notes -H "authorization: Bearer $TOKEN"
```

## Scripts

| Script | Purpose |
| --- | --- |
| `npm run dev` | Start with hot reload (`tsx watch`) |
| `npm run build` | Compile TS to `dist/` |
| `npm start` | Run compiled build |
| `npm test` | Run Jest suite |
| `npm run lint` / `format` | ESLint / Prettier |
| `npm run prisma:migrate:dev` | Create + apply migration (dev) |
| `npm run prisma:migrate` | Apply migrations (prod) |
| `npm run prisma:studio` | Open Prisma Studio |
| `npm run db:seed` | Seed database |

## Environment

See `.env.example`. Required in all environments: `DATABASE_URL`, `JWT_SECRET` (>= 16 chars).

## Kubernetes deploy (Helm + ArgoCD)

Chart lives at `deploy/helm/backend-api`, ArgoCD manifests at `deploy/argocd`.

### Dry-run / render locally

```bash
helm template backend-api deploy/helm/backend-api \
  -f deploy/helm/backend-api/values.yaml \
  -f deploy/helm/backend-api/values-dev.yaml
```

### Install directly with Helm

```bash
helm upgrade --install backend-api deploy/helm/backend-api \
  --namespace backend-api-dev --create-namespace \
  -f deploy/helm/backend-api/values-dev.yaml \
  --set image.tag=dev
```

The chart provisions:
- Deployment (with rolling update, probes, non-root securityContext, envFrom ConfigMap + Secret)
- Service (ClusterIP) + optional Ingress
- ConfigMap for non-secret env, Secret for `JWT_SECRET` + `DATABASE_URL`
- Prisma migrations Job (Helm `pre-install`/`pre-upgrade` hook + ArgoCD `PreSync` hook)
- Optional in-cluster Postgres StatefulSet (dev only, `postgres.enabled: true`)
- Optional HPA, PDB, ServiceAccount, topology spread

### Deploy via ArgoCD

```bash
# once per cluster
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# point at your repo, then:
kubectl apply -f deploy/argocd/project.yaml
kubectl apply -f deploy/argocd/application-dev.yaml
```

Both Applications use `automated: { prune: true, selfHeal: true }` and
`ServerSideApply=true`. Prod (`values-prod.yaml`) expects `secrets.existingSecret`
so credentials come from External Secrets / Sealed Secrets / Vault — not from
Git. See `deploy/argocd/README.md` for details.

## Infrastructure (Terraform)

`terraform/` provisions the container registry and IAM plumbing:

- **ECR repository** with `IMMUTABLE` tags, `scan_on_push`, AES256, and a lifecycle policy (expire untagged after 7d, keep last 30 `v*` + 50 `sha-*` images)
- **GitHub Actions OIDC federation** — a role scoped by `sub` claim to specific branches (`main`, `release/*`) and tag patterns (`v*.*.*`). No long-lived AWS keys anywhere in GitHub.
- **Reusable pull policy** — attach to your EKS node role or an IRSA role for cross-account/pod-scoped pull

Bootstrap:

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # edit github_owner + github_repo
terraform init && terraform apply
```

Then wire the outputs into GitHub (Settings → Secrets and variables → Actions → **Variables**, not Secrets — these values aren't sensitive):

| Variable | Value |
| --- | --- |
| `AWS_REGION` | `us-east-1` |
| `ECR_REGISTRY` | `<account>.dkr.ecr.<region>.amazonaws.com` |
| `ECR_REPOSITORY` | `backend-api` |
| `AWS_ROLE_TO_ASSUME` | `terraform output -raw github_push_role_arn` |

Update `image.repository` in `deploy/helm/backend-api/values.yaml` to `<account>.dkr.ecr.<region>.amazonaws.com/backend-api`. See `terraform/README.md` for full details.

## CI / CD (GitHub Actions)

Five workflows under `.github/workflows/`:

| Workflow | Trigger | Does |
| --- | --- | --- |
| `ci.yml` | PR + push to `main` | npm ci → Prisma generate → lint → build (typecheck) → Jest against real Postgres service → `helm lint` + `helm template` → docker build (no push, PR only) |
| `security.yml` | PR + push to `main` + weekly cron | CodeQL (JS/TS), `npm audit`, Trivy fs (deps), Trivy config (Dockerfile + rendered Helm), Gitleaks. All findings uploaded to the **Security** tab as SARIF. |
| `cd-dev.yml` | push to `main` (src/prisma/Dockerfile paths) | AWS OIDC → build + push multi-arch image to **ECR** tagged `sha-<short>`, **Trivy image scan** (fails on CRITICAL), then bump `values-dev.yaml` `image.tag` and commit back. ArgoCD picks it up. |
| `release.yml` | tag `v*.*.*` (or manual) | AWS OIDC → build + push semver-tagged image (immutable), then open a PR against `release/prod` bumping `values-prod.yaml` `image.tag`. Merging the PR = production rollout. |
| `promote.yml` | manual dispatch | Promote an already-built image between environments. Reads source env's current `image.tag`, verifies it exists in ECR, then opens a PR bumping the target env. **GitHub Environment approval gates** on `staging` + `production`. |

### Promotion flow

```
main branch push        →  cd-dev.yml       →  values-dev.yaml    →  ArgoCD dev
       ↓ (manual promote in Actions UI, staging approvers approve)
                        →  promote.yml      →  values-staging.yaml→  ArgoCD staging
       ↓ (manual promote in Actions UI, production approvers approve)
                        →  promote.yml      →  values-prod.yaml   →  ArgoCD prod
                           (opens PR to release/prod for merge)

git tag v1.2.3          →  release.yml      →  values-prod.yaml   →  PR to release/prod
                           (semver-tagged release image; skips staging)
```

The image itself is **never rebuilt** during promotion — the same digest that soaked in dev/staging is what reaches prod. `promote.yml` calls `aws ecr describe-images` to verify the tag exists before opening the PR.

### GitHub Environments (approval gates)

Under **Settings → Environments**, create:
- `staging` — 1 required reviewer
- `production` — 2 required reviewers, wait timer optional (e.g. 5 min)

The `promote.yml` job's `environment:` field pins the job to the target env, so GitHub blocks the run until approvers click *Approve*.

### Security scanning gates

| Scan | Blocks CI on | Notes |
| --- | --- | --- |
| CodeQL (`security-and-quality` pack) | high-severity JS/TS alerts | GitHub-native SAST |
| `npm audit --omit=dev` | HIGH+ in prod deps | Dev-dep audit is informational only |
| Trivy fs | CRITICAL | HIGH is reported to Security tab but doesn't fail the build |
| Trivy config (Dockerfile + Helm) | HIGH+ misconfig | Runs against fully rendered manifests, not just chart source |
| Trivy image (in `cd-dev.yml`) | CRITICAL in pushed image | Blocks the `values-dev.yaml` bump — a vulnerable image never reaches ArgoCD |
| ECR native scan (`scan_on_push`) | (informational) | Amazon Inspector, viewable in ECR console |
| Gitleaks | any leak | Uses `.gitleaks.toml` allowlist for test/example placeholders |

Suppress noisy false positives via `.trivyignore` (per-CVE) or `.gitleaks.toml` (per-pattern). Every suppression must be commented.

### Required repo settings

- **Actions permissions**: Settings → Actions → General → Workflow permissions = **Read and write** (needed for the auto-bump commits and release PRs).
- **Packages**: image pushes go to GHCR under the repo namespace using the default `GITHUB_TOKEN`. No extra secret required.
- **Branch protection on `main`**: allow the `github-actions[bot]` to push (or route bumps through a PR by swapping the direct-commit step in `cd-dev.yml` for `peter-evans/create-pull-request`).
- **`release/prod` branch**: create it once (`git switch -c release/prod && git push -u origin release/prod`) — the release workflow opens PRs against it.

### Notes on the GitOps handoff

- The bump commit in `cd-dev.yml` uses the default `GITHUB_TOKEN`, which by design does **not** trigger further workflow runs. If you want CI to re-run on the bump commit, swap in a PAT or a GitHub App token.
- ArgoCD `application-dev.yaml` sets `image.tag: dev` as a parameter override. Once CI is bumping `values-dev.yaml`, drop that parameter so the values file is the source of truth, or the ArgoCD parameter will keep winning.
- The Docker image is pushed with SBOM + provenance attestations (build-push-action defaults).

## Notes

- **Prisma 7**: the connection URL lives in `prisma.config.ts` (read from `DATABASE_URL`), not in `schema.prisma`. The runtime client connects through the `@prisma/adapter-pg` driver adapter (see `src/db/client.ts`). `prisma.config.ts` is shipped in the Docker image so in-container `prisma migrate deploy` works.
- The initial migration (`prisma/migrations/`) is committed — the Docker image and the Helm migration Job apply it via `prisma migrate deploy`. For new schema changes, run `npm run prisma:migrate:dev -- --name <change>` and commit the new migration.
- Update `image.repository` in `deploy/helm/backend-api/values.yaml` and `repoURL` in the ArgoCD manifests before deploying.
