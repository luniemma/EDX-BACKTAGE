# Enterprise readiness roadmap

Status: **proposal — nothing here is implemented.**
Scope agreed: **Identity + RBAC** and **Observability + SLOs**.
Budget ceiling: **~$50–100/month** of AWS spend.

---

## 1. Where the project actually is

| Area | State |
| --- | --- |
| Application | Backstage, scaffolded and running locally (`:3000` / `:7007`) |
| Image build | Multi-stage Dockerfile, amd64, pushed to ECR by `cd-dev` |
| Registry | ECR with immutable tags, scan-on-push, lifecycle policy |
| IaC | Terraform in CI — plan on PRs (read-only role), apply on `main` |
| State | S3, versioned + encrypted, native locking |
| Supply chain | CodeQL, Trivy (fs/config/image), Gitleaks, yarn audit — all gating |
| **Runtime** | **None. There is no cluster and no database.** |
| **Identity** | **`guest` — anyone who reaches the URL is an authenticated user.** |
| **Observability** | **None beyond container stdout.** |

The delivery pipeline is in good shape. What is missing is everything that
makes the portal *safe* and *operable*.

---

## 2. The budget problem — read this first

The agreed ceiling is $50–100/month. That does not fit an EKS-based
deployment, and it is better to say so now than to discover it after a
`terraform apply`:

| Item | Monthly |
| --- | --- |
| EKS control plane | $73 |
| Smallest usable node capacity | ~$30 |
| NAT gateway (1) | $33 |
| RDS `db.t4g.micro`, single-AZ | ~$15 |
| **Total** | **~$151** |

That is already 1.5× the ceiling *before* load balancers, storage, or data
transfer — and it buys a single-AZ, no-failover setup that would not be called
enterprise by any reasonable definition.

**Options that do fit the budget:**

| Option | Monthly | Trade-off |
| --- | --- | --- |
| **Local `kind` cluster** (you already run one) | **$0** | Not internet-reachable; perfect for building and demoing identity + observability |
| **ECS Fargate + RDS `t4g.micro`** | ~$45–70 | No Kubernetes, so the Helm chart and ArgoCD work goes unused |
| **App Runner + RDS** | ~$50–75 | Simplest, least control, same caveat |
| EKS anything | $150+ | Over budget |

**Recommendation:** build both selected workstreams against the local `kind`
cluster. Neither identity nor observability needs cloud infrastructure to be
implemented or verified, and doing it this way costs nothing while keeping the
Helm/ArgoCD path intact for whenever the budget allows a real cluster.

This roadmap assumes that. Where a step would differ on EKS, it says so.

---

## 3. Workstream A — Identity + RBAC

### Why this is first

`app-config.production.yaml` currently ships:

```yaml
auth:
  providers:
    guest: {}
```

Every visitor is signed in as `user:development/guest`. The catalog is
world-readable and world-writable, and the scaffolder — which holds a GitHub
token capable of creating repositories — is world-executable. **This is the
single most serious gap in the project.** Any deployment beyond localhost must
fix it first.

### A1. Replace guest with a real identity provider

Two viable choices:

**GitHub OAuth** — the natural fit, since the catalog and scaffolder already
integrate with GitHub, and the org is the source of truth for users.

**Generic OIDC** — required if the company standard is Okta, Entra ID, or
Google Workspace. Backstage's `oidc` provider covers all three.

Work involved:

- Register an OAuth app (callback `https://<host>/api/auth/github/handler/frame`)
- Add `auth.providers.github` with `clientId` / `clientSecret` from env
- Add `auth.session.secret` — required once real sign-in is enabled
- Replace the guest `SignInPage` in `packages/app/src/App.tsx`
- Add a **sign-in resolver** mapping the external identity to a catalog `User`
  entity (`usernameMatchingUserEntityName`)

> The sign-in resolver is the step people skip. Without a matching `User`
> entity in the catalog, sign-in succeeds but ownership and permissions have
> nothing to resolve against, and every "is this yours?" check silently fails.
> A1 and A2 must ship together.

### A2. Ingest users and groups

Add `GithubOrgEntityProvider` (or `GithubMultiOrgEntityProvider`) so `User` and
`Group` entities come from the GitHub org on a schedule, rather than the static
`examples/org.yaml` the scaffold ships. Teams become groups; group membership
drives ownership and permissions.

Needs a token with `read:org`.

### A3. Turn on the permission framework

Backstage ships permissions **disabled**. Enabling it means:

- `permission.enabled: true`
- Add `@backstage/plugin-permission-backend` and a policy module to
  `packages/backend`
- Write the policy

A sensible starting policy for an internal portal:

| Action | Rule |
| --- | --- |
| Read catalog | any authenticated user |
| Update / delete entity | owner group only (`isEntityOwner`) |
| Register new component | any authenticated user |
| Execute scaffolder template | any authenticated user |
| Read scaffolder task logs | task creator or owner group |
| Access admin/settings pages | platform group only |

Deny-by-default is the wrong first move here — it produces a portal nobody can
use and a flood of support requests. Start read-open/write-owned, then tighten.

### A4. Harden service-to-service auth

`backend.auth.keys` needs a real `BACKEND_SECRET` (`openssl rand -base64 32`).
The chart already plumbs it; it is currently a placeholder string in
`values.yaml` that must not survive to any shared environment.

### Deliverables

- `app-config.production.yaml` — auth providers, session, permissions
- `packages/app/src/App.tsx` — real sign-in page
- `packages/backend/src/index.ts` + a policy module
- Chart: `AUTH_GITHUB_CLIENT_ID`, `AUTH_GITHUB_CLIENT_SECRET`,
  `AUTH_SESSION_SECRET` added to the Secret
- Docs: how to register the OAuth app, required scopes

### Verification

Not "it starts" — actually exercised:

1. Sign in as yourself; confirm the identity maps to a catalog `User`
2. Confirm an entity you do **not** own cannot be edited
3. Confirm sign-out and session expiry behave
4. Confirm an unauthenticated request to `/api/catalog/entities` is rejected

### Risks

- **Lockout.** A wrong policy can lock every user, including you, out of the
  portal. Keep guest auth available behind a local-only config until the
  policy is proven.
- **Secret sprawl.** Four new secrets. They must come from a real store, not
  `values.yaml`.
- **Ownership churn.** Turning on `isEntityOwner` will surface every entity
  with a missing or wrong `spec.owner`. Expect cleanup.

---

## 4. Workstream B — Observability + SLOs

### B1. Signals

Backstage's backend is a normal Node service; nothing exotic is needed.

| Signal | Approach |
| --- | --- |
| **Metrics** | Backstage exposes Prometheus metrics from the backend; scrape it |
| **Traces** | OpenTelemetry Node SDK loaded via `--require`, exporting OTLP |
| **Logs** | Already structured (winston → stdout); ship from the cluster |

Tracing matters more than usual here: a slow catalog page is usually a slow
*processor* or a slow database query, and without spans you are guessing.

### B2. Where it goes (budget-constrained)

| Option | Cost | Notes |
| --- | --- | --- |
| **Grafana Cloud free tier** | **$0** | 10k series, 50 GB logs, 50 GB traces. Comfortably fits one portal. **Recommended.** |
| `kube-prometheus-stack` in `kind` | $0 | Fully local, nothing leaves the machine; you operate it |
| AWS Managed Prometheus + Grafana | ~$10–30 | Only sensible once running on EKS |

### B3. SLOs

A developer portal is not a payments API — the targets should reflect that.

| SLO | Target | Window | Measured by |
| --- | --- | --- | --- |
| Availability | 99.5% | 30d | Synthetic `GET /api/catalog/entities?limit=1` (authenticated), **not** the health endpoint |
| Catalog latency (p95) | < 2s | 30d | Server-side histogram on catalog queries |
| API latency (p99) | < 1s | 30d | Backend request histogram |
| Catalog freshness | < 30 min | 7d | Entity `lastUpdated` lag |
| Scaffolder success rate | > 95% | 30d | Task outcomes, excluding user-input errors |

99.5% ≈ 3.6 h/month of error budget. For an internal tool that is honest;
promising 99.9% invites alert fatigue for no real gain.

> Availability must be probed against a real authenticated query. The health
> endpoint returns 200 whenever the process is alive — including when the
> database is unreachable and every page is broken. Health checks answer
> "should Kubernetes restart this?", not "does it work?".

### B4. Alerts

Alert on symptoms users feel, not on every metric:

| Alert | Condition | Severity |
| --- | --- | --- |
| Portal down | Synthetic probe fails 3× consecutively | page |
| Error rate | 5xx > 2% over 10 min | page |
| DB pool saturated | > 90% for 5 min | ticket |
| Catalog processing errors | error rate rising over 30 min | ticket |
| Catalog stale | no successful refresh in 1 h | ticket |
| Scaffolder failures | > 20% over 1 h | ticket |
| Cert expiry | < 14 days | ticket |

Two paging alerts, the rest ticketing. More pages than that for an internal
portal means nobody reads them.

### B5. Runbook

`docs/RUNBOOK.md` covering the failures that actually happen: portal returns
5xx, catalog stale, scaffolder tasks failing, database connection exhaustion,
OAuth outage, certificate expiry. Each with symptom → check → fix → escalate.

### Deliverables

- `packages/backend/src/instrumentation.ts` + `--require` wiring
- Chart: metrics port/annotations, OTLP endpoint config
- Dashboard JSON (committed, not click-configured)
- Alert rules (committed)
- `docs/RUNBOOK.md`, `docs/SLO.md`

### Verification

Break things on purpose and confirm the signal fires: stop the database and
confirm the pool alert; force a scaffolder failure and confirm the rate moves;
confirm a trace shows an end-to-end catalog request.

---

## 5. Sequence

| Phase | Work | Depends on | Cost |
| --- | --- | --- | --- |
| **0** | Decide runtime target (`kind` vs ECS vs deferred EKS) | — | $0 |
| **1** | A1 + A2 — real IdP, user/group ingestion, resolver | 0 | $0 |
| **2** | A3 + A4 — permission policy, backend secret | 1 | $0 |
| **3** | B1 + B2 — instrumentation, metrics/traces to Grafana Cloud | 0 | $0 |
| **4** | B3–B5 — SLOs, alerts, runbook | 3 | $0 |
| **5** | *(deferred)* RDS + EKS + ExternalDNS + TLS | budget increase | $150+ |

Phases 1–4 all land at **$0/month** and are each independently reviewable.
Phase 5 is deliberately parked until the budget question is settled.

---

## 6. Not in scope (and why)

Chosen against for now, recorded so the gaps are explicit:

- **RDS** — the chart still points at a single-pod in-cluster Postgres with no
  backups and no failover. Fine for `kind`; **not** acceptable for anything
  shared. This is the first thing to add when the budget allows.
- **EKS / networking** — over budget, per §2.
- **TechDocs** — needs object storage; cheap to add later.
- **ECR repository rename** — still `backend-api`. Cosmetic; needs a
  destroy/recreate that `force_delete = false` blocks while images exist.
- **Multi-arch images** — amd64 only; arm64 under QEMU is too slow for CI.
- **DR / backup testing** — meaningless until there is a managed database.

---

## 7. Definition of done

For the two agreed workstreams:

- [ ] No path reaches the portal as `guest`
- [ ] Every user resolves to a catalog `User` entity from the org
- [ ] A non-owner cannot modify an entity they do not own — demonstrated
- [ ] All four auth secrets come from a secret store, not `values.yaml`
- [ ] Metrics, traces, and logs all visible for a single request
- [ ] Dashboard and alert rules committed to the repo
- [ ] Availability SLO measured by an authenticated synthetic probe
- [ ] Runbook exists and has been walked through once
