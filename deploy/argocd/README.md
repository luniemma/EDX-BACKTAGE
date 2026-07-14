# ArgoCD bootstrap

These manifests assume ArgoCD is already installed in the `argocd` namespace.

## Install ArgoCD (once per cluster)

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

## Wire up this app

1. Edit `project.yaml` and both `application-*.yaml` files to point `sourceRepos` / `repoURL` at your real Git repo.
2. Apply:

   ```bash
   kubectl apply -f deploy/argocd/project.yaml
   kubectl apply -f deploy/argocd/application-dev.yaml
   # kubectl apply -f deploy/argocd/application-prod.yaml   # when ready
   ```

3. ArgoCD will create the `backend-api-dev` namespace, run the Prisma
   migrations Job (via the `PreSync` hook), then roll out the Deployment.

## Prod secrets

`values-prod.yaml` sets `secrets.create: false` and points at
`secrets.existingSecret: backend-api-prod-secrets`. You are responsible for
provisioning that Secret out-of-band, e.g. via:

- [External Secrets Operator](https://external-secrets.io/) pulling from AWS Secrets Manager / GCP Secret Manager / Vault
- [Sealed Secrets](https://sealed-secrets.netlify.app/) committed alongside the chart
- ArgoCD Vault Plugin

Required keys in the Secret:

```
JWT_SECRET      (>= 16 chars)
DATABASE_URL    postgresql://user:pass@host:5432/db?schema=public
```

## Image updates

For automatic image updates on new tags, install
[argocd-image-updater](https://argocd-image-updater.readthedocs.io/) and add
annotations to the Application, e.g.:

```yaml
metadata:
  annotations:
    argocd-image-updater.argoproj.io/image-list: api=ghcr.io/your-org/backend-api
    argocd-image-updater.argoproj.io/api.update-strategy: semver
    argocd-image-updater.argoproj.io/write-back-method: git
```
