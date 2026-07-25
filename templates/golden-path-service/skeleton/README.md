# ${{ values.name }}

${{ values.description }}

Scaffolded from the **Golden Path Service** template.

## What came with it

| Path | Purpose |
| --- | --- |
| `.github/workflows/ci.yml` | Build and test on every push and PR |
| `deploy/argocd-application.yaml` | ArgoCD Application — **not applied automatically** |
| `deploy/serviceregistry.yaml` | Crossplane claim for a container registry |
| `catalog-info.yaml` | Registers this service in Backstage |

## Deploying it

The ArgoCD Application is committed but not applied. A platform operator runs:

```bash
kubectl apply -f deploy/argocd-application.yaml
```

That handoff is deliberate: scaffolding a repo should not grant write access
to the cluster.

## Owner

${{ values.owner }}
