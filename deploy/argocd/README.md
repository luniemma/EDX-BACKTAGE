# ArgoCD bootstrap

These manifests assume ArgoCD is already installed in the `argocd` namespace.

## Install ArgoCD (once per cluster)

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

## Wire up this app

1. `repoURL` / `sourceRepos` already point at
   `https://github.com/luniemma/EDX-BACKTAGE.git`. Change them if you forked.
2. Apply:

   ```bash
   kubectl apply -f deploy/argocd/project.yaml
   kubectl apply -f deploy/argocd/application-dev.yaml
   # kubectl apply -f deploy/argocd/application-prod.yaml   # when ready
   ```

3. ArgoCD creates the `rhdh-dev` namespace and rolls out the Deployment. There
   is no migration hook — Backstage runs its own Knex migrations on startup.

## Wire up scaffolded services

`applicationset-services.yaml` is what makes the golden-path template
self-service. It watches `gitops/services/*/*/config.yaml` in this repo and
turns every entry into an Application, so a service onboards by CI committing a
file — not by anyone running `kubectl`.

```bash
kubectl apply -f deploy/argocd/project-services.yaml
kubectl apply -f deploy/argocd/applicationset-services.yaml
```

Apply the project first; the ApplicationSet renders Applications into it, and
they will be rejected if it does not exist yet.

With an empty ledger this generates zero Applications, which is the correct
resting state — not a sign it is broken. Check it is watching:

```bash
kubectl get applicationset services -n argocd -o jsonpath='{.status.conditions}'
```

The ledger schema, and how to split it into a dedicated repo later, are in
[gitops/README.md](../../gitops/README.md).

Two things to know before the first service lands:

- **CI needs write access to this repo.** Scaffolded repos get an `APP_TOKEN`
  secret for that. Until the ledger lives in its own repo, that token can write
  anywhere in this one — branch protection on `main` is the only thing narrowing
  it, which is the main argument for doing the split.
- **ECR pull secrets are not provisioned.** The Composition creates the
  repository; nothing creates the `imagePullSecrets` entry the chart expects, and
  ECR tokens expire every 12 hours. Services pulling from ECR need External
  Secrets Operator or an equivalent refresher in their namespace.

Expect the first rollout to take a couple of minutes: Backstage initialises
every plugin and applies migrations before it reports ready. The chart's
readiness probe allows for this (`initialDelaySeconds: 30`, 6 failures); if you
tighten it, the kubelet will kill the pod mid-startup and it will crashloop.

## Database

- **dev** — `backstage.upstream.postgresql.enabled: true` brings up an
  in-cluster StatefulSet, and the chart injects `POSTGRES_HOST`, `POSTGRES_PORT`,
  `POSTGRES_USER` and the generated password itself. Single pod, no backups, no
  failover. Dev only.
- **staging / prod** — the subchart is off and the RDS endpoint goes in
  `appConfig.backend.database.connection.host`. Nothing in `terraform/`
  provisions that yet; see "Known gaps" in the root README.

`deploy/helm/rhdh/templates/validate.yaml` fails the render when the subchart is
off and no host is set, rather than deploying a pod that cannot reach a database.

One RHDH-specific trap: even with the in-cluster PostgreSQL disabled, the chart
still injects `POSTGRESQL_ADMIN_PASSWORD` from a Secret, and by default looks for
one named `<release>-postgresql` that nothing creates. `values-staging.yaml` and
`values-prod.yaml` repoint it via `global.postgresql.auth.existingSecret`.

## Staging / prod secrets

Neither environment lets the chart create anything. Both point at a Secret you
provision out-of-band, e.g. via:

- [External Secrets Operator](https://external-secrets.io/) pulling from AWS Secrets Manager / GCP Secret Manager / Vault
- [Sealed Secrets](https://sealed-secrets.netlify.app/) committed alongside the chart
- ArgoCD Vault Plugin

Required keys in `backstage-{staging,prod}-secrets`:

```
postgres-password          password for the database user
backend-secret             backend-to-backend auth; openssl rand -base64 32
AUTH_GITHUB_CLIENT_ID      GitHub OAuth app — sign-in fails to start without it
AUTH_GITHUB_CLIENT_SECRET  ditto
GITHUB_TOKEN               optional — PAT for catalog ingestion / scaffolder
```

The first two are lower-case-with-hyphens because the chart reads them by key
name, not as environment variables; the rest are read as environment variables
and must match exactly. Database host, port and user are **not** secrets and live
in the values file.

## Image updates

The image is Red Hat's, pinned in `deploy/helm/rhdh/values.yaml` and in
`Chart.yaml`'s `appVersion`. There is nothing to promote between environments —
every environment runs the same tag, and upgrading means editing those two
fields together and letting it flow dev → staging → prod through the normal
branch flow.

`argocd-image-updater` is deliberately not wired up: it would move the tag
without moving `appVersion` or the pinned `global.catalogIndex.image.tag`, which
is exactly the drift the pinning is there to prevent.
