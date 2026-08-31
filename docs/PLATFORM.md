# Platform guide

Everything needed to stand up, operate, debug and tear down the EKS platform
that runs Red Hat Developer Hub.

Read [Bootstrap](#bootstrap) first if nothing exists yet — the CI roles are
created by the configuration CI runs, so the first apply cannot come from CI.

---

## Architecture

```
                    ┌──────────────────────────────────────────┐
   internet ──NLB──▶│ ingress-nginx        VPC 10.42.0.0/16    │
                    │      │                                   │
                    │      ▼               public  /20 × 2 AZ  │
                    │   RHDH ──────┐       (nodes, NLB)        │
                    │   ArgoCD     │                           │
                    │              ▼       private /20 × 2 AZ  │
                    │           RDS PostgreSQL  (no egress)    │
                    └──────────────────────────────────────────┘
```

Three Terraform roots, three state keys, applied in order. They are separate
because each has a different lifecycle and a different blast radius.

| Root | Owns | State key |
| --- | --- | --- |
| `terraform/platform` | VPC, EKS 1.31, Spot node group, EBS CSI, CI roles | `edx/platform/…` |
| `terraform/platform-db` | RDS PostgreSQL, subnet group, security group | `edx/platform-db/…` |
| `terraform/platform-addons` | ingress-nginx, ArgoCD, gp3 StorageClass | `edx/platform-addons/…` |

**Why three and not one.** The addons' `kubernetes` and `helm` providers
authenticate against an endpoint that does not exist until the cluster is
applied; configuring a provider from a resource created in the same apply
breaks `plan` on clean state and makes `destroy` unreliable. The database is
separate for a different reason: teardowns are routine, and a database sharing
the cluster's state would be destroyed every time one ran.

**RHDH is deployed by ArgoCD, not Terraform.** Terraform's job stops at
installing the thing that does continuous delivery. Giving the chart two
owners that both reconcile it produces a fight over the same objects.

### Repository map

| Path | What it is |
| --- | --- |
| `terraform/platform/` | Cluster and networking. Has its own README. |
| `terraform/platform-db/` | Database, plus the data-migration procedure. |
| `terraform/platform-addons/` | Cluster-internal software. |
| `terraform/` | Unrelated: ECR and OIDC roles for the old `backend-api`. |
| `deploy/helm/rhdh/` | The RHDH wrapper chart and its value profiles. |
| `deploy/argocd/` | AppProject and Application manifests. |
| `.github/workflows/platform.yml` | Plan on PR, apply on main, health verify. |
| `.github/workflows/destroy.yml` | Ordered teardown, manual dispatch only. |

### Value profiles

| Profile | Database | TLS | Use |
| --- | --- | --- | --- |
| `values-dev.yaml` | in-cluster pod | cert-manager | minikube / kind |
| `values-lean.yaml` | **RDS** | none | this EKS platform |
| `values-staging.yaml` | external | cert-manager | not provisioned |
| `values-prod.yaml` | external | cert-manager | not provisioned |

---

## Bootstrap

Needed once, on an account with no platform in it.

**Prerequisites**

- Terraform ≥ 1.11, AWS CLI v2, `kubectl`, `helm` 3.16+, `gh`
- AWS credentials that can create IAM roles
- The state bucket `edx-backtage-tfstate-724772096574` must already exist
- Repository variable `AWS_REGION` set to `us-east-1`

**The ordering problem.** `platform.yml` runs under `edx-rhdh-tf-apply`, and
that role is created by `terraform/platform`. So the first apply has to run
locally:

```bash
terraform -chdir=terraform/platform        init && terraform -chdir=terraform/platform        apply
terraform -chdir=terraform/platform-db     init && terraform -chdir=terraform/platform-db     apply
terraform -chdir=terraform/platform-addons init && terraform -chdir=terraform/platform-addons apply
```

Then publish both role ARNs so CI can take over:

```bash
gh variable set TF_PLATFORM_PLAN_ROLE_ARN \
  --body "$(terraform -chdir=terraform/platform output -raw platform_plan_role_arn)"
gh variable set TF_PLATFORM_APPLY_ROLE_ARN \
  --body "$(terraform -chdir=terraform/platform output -raw platform_apply_role_arn)"
```

> ⚠️ **Check the value before you set it**
>
> `terraform output -raw` on an output that does not exist yet prints a
> warning and no value, and `gh variable set` will happily store the ANSI
> escape codes from that warning as your role ARN. Every job then stops
> skipping and starts failing against a role named `^[[33m╷`. Confirm each
> value looks like `arn:aws:iam::…:role/…` before writing it.

Until those variables exist, every job in `platform.yml` **skips** rather than
failing — there is no role to assume, so a run could only produce a red X
meaning "not bootstrapped yet".

---

## Standing it up

```bash
gh workflow run platform.yml --ref main -f root=both
```

Apply order is `platform → platform-db → platform-addons`, then a `verify` job
that checks nodes are Ready, ArgoCD and ingress-nginx have rolled out, the load
balancer has an address, and nothing is crash-looping.

Expect **~20 minutes**: the EKS control plane is ~10, the node group ~5, RDS
~5–10 in parallel.

### Wire up RHDH

Two values cannot be committed in advance because they do not exist until the
infrastructure does.

**1. The ingress hostname.**

```bash
kubectl -n ingress-nginx get svc ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

Put it in `values-lean.yaml` as `global.host`,
`backstage.upstream.ingress.host`, and all three of `app.baseUrl`,
`backend.baseUrl` and `backend.cors.origin`.

> ℹ️ **Why the base URLs are set explicitly**
>
> The chart derives them from `global.host` as `https://<host>` — a hardcoded
> scheme. This profile terminates no TLS, so those URLs would be wrong and the
> portal would load and then fail every API call. `global.host` takes the
> hostname **with no scheme**: the chart interpolates it, so a scheme there
> yields `https://http://…`.

**2. The database endpoint.**

```bash
terraform -chdir=terraform/platform-db output -raw endpoint
```

Goes under `backstage.upstream.backstage.appConfig.backend.database.connection.host`.

Commit both — ArgoCD syncs the change. Until they are set,
`templates/validate.yaml` fails the render on purpose.

### Secrets

Two Secrets, neither created by the chart.

**Database password.** RDS generates it into Secrets Manager, so it is never in
Terraform state:

```bash
terraform -chdir=terraform/platform-db output -raw kubernetes_secret_command
```

Run that command's output. Nothing syncs these automatically — re-run it after
every rotation, or install External Secrets Operator.

**GitHub OAuth.** The portal sets `signInPage: github` with guest auth
deliberately removed, so **without real credentials nobody can log in** —
a pod that runs is not a usable portal.

```bash
kubectl -n rhdh-lean create secret generic rhdh-secrets --dry-run=client -o yaml \
  --from-literal=AUTH_GITHUB_CLIENT_ID=<id> \
  --from-literal=AUTH_GITHUB_CLIENT_SECRET=<secret> \
  --from-literal=GITHUB_TOKEN=<pat> | kubectl apply -f -
```

The OAuth App's callback URL is `http://<ingress-host>/api/auth/github/handler/frame`.

### Bootstrap ArgoCD

```bash
kubectl apply -f deploy/argocd/project.yaml
kubectl apply -f deploy/argocd/application-lean.yaml
```

ArgoCD's UI is not exposed. Reach it locally:

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:80
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
```

---

## Day-2 operations

| Task | How |
| --- | --- |
| Change infrastructure | PR → review the plan comment → merge to main |
| Change RHDH config | Edit `values-lean.yaml`, commit — ArgoCD syncs |
| Force a sync | `kubectl -n argocd patch application rhdh-lean --type merge -p '{"operation":{"sync":{}}}'` |
| Cluster access | `aws eks update-kubeconfig --region us-east-1 --name edx-rhdh` |
| Read RHDH logs | `kubectl -n rhdh-lean logs deploy/rhdh-developer-hub -c backstage-backend` |
| Plugin install logs | same pod, `-c install-dynamic-plugins` |

> 🚨 **CI applies reassign cluster admin**
>
> `enable_cluster_creator_admin_permissions = true` grants cluster admin to
> **whoever runs the apply**. When CI applies from main it replaces the
> previous access entry, and a local `kubectl` that worked five minutes ago
> starts returning `Unauthorized`. Restore with:
>
> ```bash
> aws eks create-access-entry --cluster-name edx-rhdh --region us-east-1 \
>   --principal-arn <your-arn> --type STANDARD
> aws eks associate-access-policy --cluster-name edx-rhdh --region us-east-1 \
>   --principal-arn <your-arn> --access-scope type=cluster \
>   --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy
> ```
>
> That is drift the next apply undoes. The durable fix — declaring
> `access_entries` explicitly so admin does not follow the applier — is not
> yet implemented.

---

## Teardown

```bash
gh workflow run destroy.yml --ref main \
  -f scope=everything -f confirm="destroy edx-rhdh"
```

Manual dispatch only. The confirmation phrase must match exactly, and it must
be dispatched from `main` — the apply role's trust policy pins that branch.

| Scope | Removes | Keeps |
| --- | --- | --- |
| `addons-only` | ingress-nginx, ArgoCD, the NLB | cluster, nodes, database |
| `everything` | the above + node group, control plane, VPC | **database**, CI roles |
| `everything-including-database` | all of it, leaving a final snapshot | CI roles |

### Why the order is what it is

Four constraints, three of them invisible until something has already leaked.

1. **ArgoCD Applications first**, while the controller still exists to process
   `resources-finalizer.argocd.argoproj.io`. Otherwise the namespace wedges in
   `Terminating` and the destroy cannot finish.
2. **PVCs before the cluster.** A StatefulSet's `volumeClaimTemplates` PVCs are
   retained deliberately when the StatefulSet goes, and nothing else deletes
   them. Destroy the cluster around them and the CSI driver that owned the EBS
   volumes no longer exists to clean up — they bill forever with no Kubernetes
   object and no state file referring to them.
3. **Addons before the cluster.** The NLB belongs to the ingress-nginx Service,
   not to Terraform; deleting the Service is what deletes the load balancer.
   The workflow polls until no load balancers remain and refuses to continue
   otherwise.
4. **A targeted destroy for the cluster.** An untargeted one includes
   `aws_iam_role.platform_apply` — the role the job is authenticated as — so
   Terraform would delete its own credentials partway through.

### What survives, deliberately

- `edx-rhdh-tf-plan` and `edx-rhdh-tf-apply`. IAM roles are free, and see (4).
- The KMS key enters a **30-day mandatory deletion window** and bills ~$1/month
  until it expires. This cannot be shortened.
- A final RDS snapshot, if the database was destroyed. It bills until deleted.

### Verifying nothing was left

```bash
aws eks list-clusters --region us-east-1
aws ec2 describe-instances --region us-east-1 \
  --filters Name=instance-state-name,Values=running --query 'length(Reservations[].Instances[])'
aws ec2 describe-volumes  --region us-east-1 --query 'length(Volumes)'
aws elbv2 describe-load-balancers --region us-east-1 --query 'length(LoadBalancers)'
aws ec2 describe-vpcs --region us-east-1 --query 'Vpcs[?IsDefault==`false`].VpcId'
```

Volumes and load balancers are the two that have actually leaked in practice.

---

## Troubleshooting

Every entry below was hit for real. Symptom first, because that is what you
have when you arrive.

### `no repository definition for …rhdh-chart`

`helm dependency build` resolves the repo URL against the runner's own list,
which starts empty. Add `helm repo add` before it. Passes locally because
developers already have the repo added.

### Node group times out after exactly one hour

```
timeout while waiting for state to become 'ACTIVE' (last state: 'CREATING')
```

Check `kubectl get nodes` — if they are `NotReady` with `cni plugin not
initialized` and `kube-system` has **no pods at all**, the CNI addon is
scheduled after the node group. `vpc-cni` and `kube-proxy` need
`before_compute = true`; a node cannot become Ready without a CNI, and the
addon will not install until the node group is Ready.

### A Service stays `<pending>` with `Events: <none>`

An empty event list means nothing tried, not that something failed. Almost
always `aws-load-balancer-type: "external"`, which defers the Service to the
AWS Load Balancer Controller. If that controller is not installed the Service
has no owner. Use `"nlb"` to keep the in-tree provider responsible.

### Pod `Pending` on `unbound immediate PersistentVolumeClaims`

Check `kubectl get sc` for a `(default)` marker. EKS ships gp2 but does **not**
mark it default, so a cluster can easily have none. RHDH's
`dynamic-plugins-root` is a generic ephemeral volume with no
`storageClassName`, so it needs a default to exist.

### `Permission denied` writing to a mounted volume

```
mkdir: cannot create directory '/var/lib/pgsql/data/userdata': Permission denied
PermissionError: '/dynamic-plugins-root/install-dynamic-plugins.lock'
```

Missing `fsGroup`. A freshly provisioned EBS volume is root-owned and these
images run non-root. `fsGroup` is **not** `runAsUser` — it does not pin a UID,
it tells the kubelet which group to chown the volume to. On OpenShift the SCC
does this; on vanilla EKS nothing does. Postgres wants 26, RHDH wants 1001.

### `CreateContainerConfigError: secret "rhdh-secrets" not found`

The chart never creates it. See [Secrets](#secrets).

### `AccessDenied: ssm:GetParameter on …/aws/service/eks/optimized-ami/…`

The EKS module resolves the node AMI version from a public SSM parameter on
every plan **and** apply. Both CI roles need `ssm:GetParameter` on
`aws/service/eks/*`. Invisible locally, because a developer identity is
broadly privileged.

### `AccessDenied: iam:DetachRolePolicy on role default-eks-node-group-…`

The node group role was named from the node group *key*, not the cluster, so it
fell outside the `edx-rhdh-*` prefix the CI roles are scoped to. Fixed by
setting `iam_role_name` explicitly — but if you see this, a role was orphaned
and needs deleting by hand after detaching its three managed policies.

### `kubectl` suddenly returns `Unauthorized`

A CI apply took the access entry. See the warning under
[Day-2 operations](#day-2-operations).

### The portal loads but every API call fails

`app.baseUrl` / `backend.baseUrl` do not match how the browser actually reaches
the portal — usually `https` where the NLB serves plain HTTP. Scheme, host and
port must match exactly.

### ArgoCD refuses the Application with a project error

The AppProject restricts destinations to `rhdh-*`. A bare `rhdh` does not match
that glob, and the error reads like an RBAC problem rather than a namespace
one.

---

## Cost

**~$130/month** at us-east-1 list prices, before data transfer.

| Item | ~$/month |
| --- | --- |
| EKS control plane | 73 |
| 2 × `t3.medium` Spot | 18 |
| NLB | 16 |
| RDS `db.t4g.micro` + 20 GiB gp3 + backups | 15 |
| Public IPv4 × 2 | 7 |
| 2 × 30 GiB gp3 root volumes | 5 |
| Control-plane logs (api + authenticator, 7 days) | <1 |

**The control plane is 57% of the total and is not reducible while this is
EKS.** Everything under it is already trimmed: Spot rather than on-demand,
one shared NLB rather than an ALB per Ingress, no NAT gateway, root volumes
sized from what lands on them, the audit log dropped from control-plane
logging, and ArgoCD's dex and notifications controllers disabled because
nothing here configures SSO or a notification destination.

RDS is at its floor: `db.t4g.micro` is the smallest PostgreSQL class, 20 GiB
the minimum for gp3, and Performance Insights, enhanced monitoring and
Multi-AZ are all off.

### If it still costs too much

| Change | Saves | Cost to you |
| --- | --- | --- |
| k3s on one EC2 instead of EKS | ~$95 | Managed control plane, EKS addons, IRSA |
| `node_desired_size = 1` | ~$14 | All redundancy — a Spot reclamation takes the platform down until a node rejoins |
| NodePort instead of the NLB | $16 | A stable URL; node IPs churn with Spot replacements |
| Drop RDS, return to the in-cluster pod | $15 | Backups, and surviving the cluster |

Only the first changes the order of magnitude. **This is the cheapest EKS,
not the cheapest platform** — if the target is genuinely lowest cost, EKS is
the wrong base.

> ℹ️ **Against the documented budget**
>
> `XETA-DEPLOYMENT.md` sets a ~$50–100/month ceiling for this project. The
> control plane alone is $73, so **any** EKS build breaks that ceiling before
> a node starts. This is the cheapest honest EKS, not a cheap deployment.

**Deliberate reductions:** no NAT gateway (−$33, nodes in public subnets), Spot
capacity (−~$40 vs on-demand), single-AZ RDS (−~$12), one shared NLB rather
than an ALB per Ingress.

---

## Security posture

Four Trivy findings are suppressed in `.trivyignore` — three CRITICAL, one
HIGH. All are consequences of the no-NAT profile rather than oversights, and
they are grouped so the trade is reviewed once.

| Rule | Finding | Why it stands |
| --- | --- | --- |
| `AVD-AWS-0040/0041` | Public EKS endpoint on `0.0.0.0/0` | No NAT, bastion or VPN, so a private-only endpoint locks out operators and Terraform. Also load-bearing for CI: GitHub-hosted runners have unlistable egress. Authentication is IAM, so it is not an anonymous surface. |
| `AVD-AWS-0164` | Subnets assign public IPs | Same cause — nodes need a routable address to pull images. |
| `AVD-AWS-0104` | Unrestricted node egress | Nodes must reach quay.io and regional AWS endpoints. Filtering needs a VPC endpoint per service, costing more than the cluster. |
| `AVD-KSV-0109` | ConfigMap stores secrets | False positive: every flagged key holds a `${VAR}` placeholder expanded from a Secret at boot. |

**Hardening, in order of value per unit of effort:**

1. Narrow `var.public_access_cidrs` to a known egress range. Free, clears the
   most exposure.
2. Private subnets for nodes + one NAT gateway (+$33/mo). Clears three of four.
3. Declare `access_entries` explicitly so CI applies stop reassigning admin.
4. VPC endpoints to constrain egress. Only once the cluster holds something
   that justifies the cost.

The database is already isolated: private subnets with no internet route,
`publicly_accessible = false`, and ingress by security-group reference rather
than CIDR.

---

## Reference

**Repository variables**

| Variable | Purpose |
| --- | --- |
| `AWS_REGION` | Region for every workflow |
| `TF_PLATFORM_PLAN_ROLE_ARN` | Read-only, `pull_request` only |
| `TF_PLATFORM_APPLY_ROLE_ARN` | Read/write, `refs/heads/main` only |
| `TF_PLAN_ROLE_ARN` / `TF_APPLY_ROLE_ARN` | The unrelated ECR root |

**Workflows**

| Workflow | Trigger |
| --- | --- |
| `ci` | PR, push to main — chart renders, catalog entities |
| `security` | PR, push, weekly — Trivy, Gitleaks |
| `platform` | PR (plan), push to main (apply), dispatch |
| `destroy` | Manual dispatch only |
| `terraform` | The ECR/OIDC root only |

**Naming.** Everything the platform creates is prefixed `edx-rhdh-`, which is
what the CI roles' IAM scoping depends on. Anything new that IAM must manage
has to follow it or CI will fail on that resource alone.
