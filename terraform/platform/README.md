# Platform — lean EKS

The cluster RHDH runs on. Two Terraform roots, applied in order:

| Root | Owns | State key |
| --- | --- | --- |
| `terraform/platform` | VPC, EKS control plane, Spot node group, EBS CSI, the CI apply role | `edx/platform/terraform.tfstate` |
| `terraform/platform-addons` | ingress-nginx, ArgoCD, the `gp3` StorageClass | `edx/platform-addons/terraform.tfstate` |

They are separate because the addons' `kubernetes` and `helm` providers
authenticate against an endpoint that does not exist until the first root has
been applied. Configuring a provider from a resource created in the same apply
makes the provider config depend on an unknown value, which breaks `plan` on a
clean state and makes `destroy` unreliable.

RHDH itself is deployed by **ArgoCD**, not by Terraform — see
`deploy/argocd/application-lean.yaml`. Terraform's job stops at installing the
thing that does continuous delivery. Giving the chart two owners that both
reconcile it is how you get a fight over the same objects.

## Cost

Roughly **$115/month** before data transfer, at `us-east-1` list prices:

| Item | ~$/month |
| --- | --- |
| EKS control plane | 73 |
| 2 × `t3.medium` Spot | 18 |
| NLB (one, shared by every Ingress) | 16 |
| 2 × 40 GiB gp3 root volumes | 6 |
| Public IPv4 addresses | 7 |
| CloudWatch control-plane logs (7-day retention) | ~1 |

The control plane is 63% of that and is not reducible while this is EKS.

**What was given up to get there**, all deliberate:

- **No NAT gateway** (−$33). Nodes sit in public subnets with public IPs.
- **No RDS** (−$13). PostgreSQL runs as a single in-cluster pod on a Spot node,
  with no backups and no failover. Fine for evaluation; not for data you care
  about. `values-prod.yaml` + a real RDS instance is the answer there.
- **Spot capacity.** Nodes get reclaimed. RHDH is a stateless Deployment and
  ArgoCD re-places what gets evicted, but the database restarts with the node.

## Hardening

Four Trivy findings are suppressed in `.trivyignore`, all of them consequences
of the above rather than oversights: `AVD-AWS-0040`, `AVD-AWS-0041` (public API
endpoint open to `0.0.0.0/0`), `AVD-AWS-0164` (public-IP subnets) and
`AVD-AWS-0104` (unrestricted node egress).

In priority order:

1. **Narrow `var.public_access_cidrs`.** Highest value, zero cost. It is
   `0.0.0.0/0` only because there is no private path in and because the
   `verify` job runs on GitHub-hosted runners with dynamic egress addresses.
   The endpoint is IAM-authenticated, not an anonymous surface — but it should
   not be reachable from everywhere either.
2. **Private subnets + one NAT gateway** (+$33/month). Clears 0164, and lets
   the API endpoint go private-only, which clears 0040 and 0041 too.
3. **VPC endpoints per service** to constrain egress and clear 0104. Only worth
   it once the cluster holds something that justifies it — the endpoints cost
   more per month than the cluster does.

## Applying

Through Actions, which is the supported path:

```
gh workflow run platform.yml --ref main -f root=both
```

Requires the repository variable `TF_PLATFORM_APPLY_ROLE_ARN`, whose value is
the `platform_apply_role_arn` output of this root. That is a bootstrap
ordering problem — the role that CI uses is created by the configuration CI
applies — so the **first** apply has to run locally under credentials that can
create IAM roles:

```
cd terraform/platform      && terraform init && terraform apply
cd terraform/platform-addons && terraform init && terraform apply
```

then set the variable from the output and use the workflow from then on:

```
gh variable set TF_PLATFORM_APPLY_ROLE_ARN \
  --body "$(terraform -chdir=terraform/platform output -raw platform_apply_role_arn)"
```

## After the first apply

The RHDH Ingress needs a hostname, and the hostname is the NLB that
ingress-nginx creates, so it cannot be committed in advance:

```
kubectl -n ingress-nginx get svc ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

Put that in `deploy/helm/rhdh/values-lean.yaml` as both `global.host` and
`backstage.upstream.ingress.host`, and commit. ArgoCD syncs the change.

Until it is set, `templates/validate.yaml` fails the render on purpose — a
failed sync is a better outcome than a portal whose frontend calls an origin
that does not answer.

## Teardown

`platform-addons` first, or the NLB it created is orphaned and keeps billing:

```
terraform -chdir=terraform/platform-addons destroy
terraform -chdir=terraform/platform       destroy
```
