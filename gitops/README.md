# GitOps ledger

This directory is the deployment ledger. It records **what runs where, at which
version** — nothing else. ArgoCD reads it; humans and CI write to it through
pull requests.

`deploy/argocd/applicationset-services.yaml` watches
`gitops/services/*/*/config.yaml` and turns every file it finds into an ArgoCD
Application. Add a file, a service deploys. Delete it, the Application and its
workloads go away. Nobody runs `kubectl`.

## Layout

```
gitops/services/<service>/<env>/config.yaml
```

The directory names are for humans. ArgoCD reads the file *contents*, so the
`service.name` and `service.env` keys are what actually matter — keep them in
step with the path or the next person will be badly misled.

## Entry schema

Every key is required. The ApplicationSet runs with `missingkey=error`, so an
incomplete entry fails to render rather than producing an Application with empty
fields pointing somewhere unintended.

```yaml
service:
  name: payments-api          # ArgoCD app becomes <name>-<env>
  env: dev                    # dev | staging
  namespace: payments-api-dev # created by the sync, must match *-dev / *-staging

source:
  repoURL: https://github.com/luniemma/payments-api.git
  targetRevision: main
  path: deploy/helm           # the service's own chart, in its own repo

image:
  repository: 724772096574.dkr.ecr.us-east-1.amazonaws.com/payments-api
  tag: sha-1468cc0            # the only line CI ever rewrites
```

`namespace` must match a destination allowed by the `services` AppProject
(`*-dev` or `*-staging`). Production is not self-service and has no destination
there on purpose — promoting to prod stays a reviewed change to
`deploy/argocd/application-prod.yaml`.

## Who writes what

| Writer | Writes | When |
| --- | --- | --- |
| Backstage scaffolder | the whole entry | once, at service creation, as a PR |
| The service's CI | `image.tag` only | every green build on `main` |
| A human | anything | promotions, offboarding, fixing a bad entry |

The split matters: CI holds a token that can change a version, not one that can
repoint a service at a different repo. Widening what CI may write is a decision,
not an accident.

## Splitting this into its own repository

The ledger lives inside the platform repo today so the loop closes without
waiting on a second repo to exist. Everything is already arranged so the split
is mechanical — the ApplicationSet reads the ledger over HTTPS exactly as it
would read a separate repo.

```bash
# 1. Extract the directory with its history intact
git subtree split --prefix=gitops -b gitops-only

# 2. Create the repo and push
gh repo create luniemma/EDX-GITOPS --private
git push git@github.com:luniemma/EDX-GITOPS.git gitops-only:main

# 3. Repoint the ApplicationSet — repoURL, and drop the gitops/ path prefix
#    deploy/argocd/applicationset-services.yaml
#      repoURL: https://github.com/luniemma/EDX-GITOPS.git
#      files:
#        - path: "services/*/*/config.yaml"

# 4. Repoint the scaffolder's PR target
#    templates/golden-path-service/template.yaml → step `gitops-pr`, repoUrl input
```

Do the split when you want the access-control boundary: a separate repo lets you
give CI write access to versions without giving it write access to platform
manifests. Until then the boundary is branch protection on `main`, which is
weaker — CI pushing a tag bump and CI editing `deploy/` are the same permission.

## Why the ledger holds a pointer, not rendered manifests

The alternative is rendering each service's Helm chart to plain YAML and
committing the output here. That gives you a diffable record of exactly what
will hit the cluster, which is genuinely valuable during an incident.

It also means every chart change requires a re-render, the ledger grows without
bound, and the interesting diff — "which version is live" — gets buried in
thousands of lines of unchanged manifest. Pointers keep the ledger readable at
the cost of that record. If you later want the audit trail more than the
readability, render into `gitops/rendered/<service>/<env>/` and point the
ApplicationSet's `source.path` there instead; the rest of this design is
unaffected.
