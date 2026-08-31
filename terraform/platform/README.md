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

Requires two repository variables, `TF_PLATFORM_PLAN_ROLE_ARN` and
`TF_PLATFORM_APPLY_ROLE_ARN`. Both roles are created by this root, which is a
bootstrap ordering problem — the roles CI uses are created by the
configuration CI applies — so the **first** apply has to run locally under
credentials that can create IAM roles:

```
cd terraform/platform        && terraform init && terraform apply
cd ../platform-addons        && terraform init && terraform apply
```

then publish both ARNs and use the workflow from then on:

```
gh variable set TF_PLATFORM_PLAN_ROLE_ARN \
  --body "$(terraform -chdir=terraform/platform output -raw platform_plan_role_arn)"
gh variable set TF_PLATFORM_APPLY_ROLE_ARN \
  --body "$(terraform -chdir=terraform/platform output -raw platform_apply_role_arn)"
```

Until those variables exist, every job in `platform.yml` skips rather than
failing — there is no role to assume, so a run could only produce a red X that
means "not bootstrapped yet". `backend-api-tf-plan` and `backend-api-tf-apply`
are deliberately not reused: neither can read this root's state, and the plan
role has no EC2 or EKS read access at all.

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

Use the workflow — it enforces an ordering that is easy to get wrong by hand:

```
gh workflow run destroy.yml --ref main \
  -f scope=everything -f confirm="destroy edx-rhdh"
```

`scope=addons-only` stops after removing ingress-nginx and ArgoCD, which drops
the NLB (~$16/month) and leaves the cluster running. `scope=everything` also
destroys the node group, control plane and VPC.

Manual dispatch only, and the confirmation phrase must match exactly. It must
be dispatched from `main`: the apply role's trust policy pins that branch, and
from anywhere else the role assumption fails with an unhelpful STS error.

### Why the order matters

1. **ArgoCD Applications are deleted first.** They carry
   `resources-finalizer.argocd.argoproj.io`. Remove the ArgoCD controller
   while an Application still exists and nothing is left to process the
   finalizer, so the namespace wedges in `Terminating` and the destroy cannot
   complete.
2. **`platform-addons` is destroyed before `platform`.** The NLB belongs to
   the ingress-nginx Service, not to Terraform — deleting the Service is what
   makes the in-tree cloud provider delete the load balancer. Destroy the
   cluster first and the NLB outlives it, still billing, with nothing in any
   state file pointing at it. The workflow blocks on this: it polls until no
   load balancers remain and refuses to touch the cluster otherwise.

### What survives

The `edx-rhdh-tf-plan` and `edx-rhdh-tf-apply` roles are kept on purpose, so
the cluster job runs a *targeted* destroy rather than a bare one. An untargeted
`terraform destroy` would include `aws_iam_role.platform_apply` — the role the
job is authenticated as — and Terraform would delete its own credentials
partway through, leaving the state half-applied and the rest of the teardown
stranded.

IAM roles are free, so keeping them costs nothing and leaves the stack
re-appliable. Delete them by hand if you are retiring it for good.

Doing it locally instead, same ordering, with the same caveat about the roles:

```
terraform -chdir=terraform/platform-addons destroy
terraform -chdir=terraform/platform destroy \
  -target=aws_eks_addon.ebs_csi \
  -target=aws_iam_role_policy_attachment.ebs_csi \
  -target=aws_iam_role.ebs_csi \
  -target=module.eks \
  -target=module.vpc
```
