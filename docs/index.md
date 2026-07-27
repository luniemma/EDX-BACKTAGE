# EDX-BACKTAGE

A [Backstage](https://backstage.io) developer portal, plus the delivery platform
that ships it: container build → ECR → Helm → ArgoCD, with Crossplane for cloud
resources and Terraform for the AWS side.

These pages are built by TechDocs from the `docs/` directory of this repository.

## Where to start

| If you want to | Read |
| --- | --- |
| Take this to production, with real sign-in | [Enterprise setup](ENTERPRISE-SETUP.md) |
| Understand what is deliberately not done yet | [Enterprise roadmap](ENTERPRISE-ROADMAP.md) |
| Deploy the Xeta AI platform | [Xeta deployment](XETA-DEPLOYMENT.md) |

## The platform loop

```
Developer → Backstage → Software Template → GitHub repo → GitHub Actions
          → GitOps ledger → ArgoCD → Kubernetes → Crossplane → AWS
```

The only hand-off in that chain is code review. The scaffolder creates a
repository and never touches the cluster; the cluster changes because a commit
landed in the ledger. See `gitops/README.md` for the ledger contract.

## How these docs are built

TechDocs runs `mkdocs` inside the Backstage backend. The runtime image installs
it into a virtualenv, which is what makes `techdocs.generator.runIn: local`
work — there is no Docker daemon inside the pod for the `docker` generator to
use.

Generated output is written to `/tmp/techdocs`, because the container runs with
a read-only root filesystem and that emptyDir is the only writable path. That
also means the output is **ephemeral**: it is rebuilt after every restart, and
two replicas keep separate copies. Moving the publisher to S3 is what fixes
both, and is covered in the enterprise setup guide.
