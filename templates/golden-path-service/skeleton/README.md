# ${{ values.name }}

${{ values.description }}

Scaffolded from the **Golden Path Service** template.

## What came with it

| Path | Purpose |
| --- | --- |
| `.github/workflows/ci.yml` | Test, build the image, record the version in GitOps |
| `Dockerfile` | Builds the image CI pushes |
| `deploy/helm/` | The chart ArgoCD syncs |
| `deploy/gitops-entry.yaml` | Where this service deploys — CI copies it to the ledger |
| `deploy/serviceregistry.yaml` | Crossplane claim for a container registry |
| `catalog-info.yaml` | Registers this service in Backstage |

## How it deploys

```
push to main → CI tests → builds + pushes image to ECR
             → writes deploy/gitops-entry.yaml into the platform's GitOps ledger
             → ArgoCD's `services` ApplicationSet creates the Application
             → synced to namespace ${{ values.name }}-${{ values.deployEnvironment }}
```

Nobody runs `kubectl`. The cluster changes because a commit landed in the
ledger, and it changes back the same way — revert the commit.

To move this service, edit `deploy/gitops-entry.yaml` and open a PR. The next
green build carries the change through. CI only ever overwrites `image.tag`, so
it cannot silently repoint you at a different chart.

## Before the first build can succeed

Set these on this repository — the scaffolder cannot create them:

| Kind | Name | Why |
| --- | --- | --- |
| Variable | `AWS_ROLE_TO_ASSUME` | Role CI federates into to push to ECR |
| Variable | `AWS_REGION` | `us-east-1` |
| Secret | `APP_TOKEN` | Write access to the platform repo, so CI can record the version |

`APP_TOKEN` cannot be named `GITHUB_*` — GitHub reserves that prefix for the
token it injects itself.

If you asked for a registry, the `ServiceRegistry` claim in
`deploy/serviceregistry.yaml` has to be applied by the platform team before ECR
will accept the push.

## Running it locally

```bash
npm install
npm start          # listens on :8080, /healthz for readiness
```

## Owner

${{ values.owner }}
