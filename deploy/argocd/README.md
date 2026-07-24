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

3. ArgoCD creates the `backstage-dev` namespace and rolls out the Deployment.
   There is no migration hook — Backstage runs its own Knex migrations on
   startup.

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

- **dev** — `postgres.enabled: true` brings up an in-cluster StatefulSet. Single
  pod, no backups, no failover. Dev only.
- **staging / prod** — set `externalPostgres.host` to an RDS endpoint. Nothing in
  `terraform/` provisions that yet; see "Known gaps" in the root README.

The chart deliberately fails to render when neither is configured, rather than
deploying a pod that cannot reach a database.

## Prod secrets

`values-prod.yaml` sets `secrets.create: false` and points at
`secrets.existingSecret: backstage-prod-secrets`. You provision that Secret
out-of-band, e.g. via:

- [External Secrets Operator](https://external-secrets.io/) pulling from AWS Secrets Manager / GCP Secret Manager / Vault
- [Sealed Secrets](https://sealed-secrets.netlify.app/) committed alongside the chart
- ArgoCD Vault Plugin

Required keys:

```
POSTGRES_PASSWORD   password for externalPostgres.user
BACKEND_SECRET      backend-to-backend auth; openssl rand -base64 32
GITHUB_TOKEN        optional — PAT for catalog ingestion / scaffolder
```

`POSTGRES_HOST`, `POSTGRES_PORT` and `POSTGRES_USER` are **not** secrets and come
from the ConfigMap.

## Image updates

For automatic image updates on new tags, install
[argocd-image-updater](https://argocd-image-updater.readthedocs.io/) and add
annotations to the Application, e.g.:

```yaml
metadata:
  annotations:
    argocd-image-updater.argoproj.io/image-list: app=724772096574.dkr.ecr.us-east-1.amazonaws.com/backend-api
    argocd-image-updater.argoproj.io/app.update-strategy: semver
    argocd-image-updater.argoproj.io/write-back-method: git
```

Note the ECR repository is still named `backend-api` — see "Known gaps" in the
root README.

This overlaps with what `cd-dev.yml` already does (it bumps `values-dev.yaml`
directly). Pick one write-back mechanism, not both, or they will fight.
