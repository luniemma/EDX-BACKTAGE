# EDX-BACKTAGE

A [Red Hat Developer Hub](https://developers.redhat.com/products/rhdh) portal,
plus the delivery platform around it: Helm → ArgoCD, with Crossplane for cloud
resources and Terraform for the AWS side.

RHDH is Red Hat's build of [Backstage](https://backstage.io). It ships as a
prebuilt container image, so this repository builds no application — there is no
source tree, no Dockerfile and no image pipeline. Configuration and plugin
selection live in the Helm values at `deploy/helm/rhdh`.

These pages are built by TechDocs from the `docs/` directory of this repository.

## Where to start

| If you want to | Read |
| --- | --- |
| Configure or upgrade the portal | `deploy/helm/rhdh/README.md` |
| Take this to production, with real sign-in | [Enterprise setup](ENTERPRISE-SETUP.md) |
| Understand what is deliberately not done yet | [Enterprise roadmap](ENTERPRISE-ROADMAP.md) |
| Deploy the Xeta AI platform | [Xeta deployment](XETA-DEPLOYMENT.md) |

Both enterprise documents predate the RHDH migration and are marked with what
has changed; read those banners before following their steps.

## The platform loop

```
Developer → RHDH → Software Template → GitHub repo → GitHub Actions
          → GitOps ledger → ArgoCD → Kubernetes → Crossplane → AWS
```

The only hand-off in that chain is code review. The scaffolder creates a
repository and never touches the cluster; the cluster changes because a commit
landed in the ledger. See `gitops/README.md` for the ledger contract.

## How these docs are built

TechDocs runs `mkdocs` inside the RHDH backend. The image ships it in
`/opt/techdocs-venv` and puts it on `PATH`, which is what makes
`techdocs.generator.runIn: local` work — there is no Docker daemon inside the pod
for the `docker` generator to use. This repository no longer installs mkdocs
itself; it used to, in a Dockerfile stage that the migration deleted.

Generated output is written to `/tmp/techdocs`, because the container runs with
a read-only root filesystem and that emptyDir is the only writable path. That
also means the output is **ephemeral**: it is rebuilt after every restart, and
multiple replicas keep separate copies. Moving the publisher to S3 is what fixes
both, and is covered in the enterprise setup guide.
