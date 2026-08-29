# Terraform — ECR + GitHub OIDC roles + remote state

Provisions the container registry that CI/CD pushes into and Kubernetes pulls
from, plus the OIDC roles that let GitHub Actions do both the image push and
Terraform itself.

## What gets created

**Registry**

- `aws_ecr_repository.this` — the registry
  - `IMMUTABLE` tags (`v1.2.3` never gets overwritten)
  - `scan_on_push = true` (Amazon Inspector native scanning)
  - AES256 encryption at rest
- `aws_ecr_lifecycle_policy.this` — expire untagged after 7d, keep last 30 `v*`
  and last 50 `sha-*`
- `aws_ecr_repository_policy.cross_account_pull` — only if
  `additional_pull_account_ids` is set

**IAM**

- `aws_iam_role.github_push` — assumed by Actions via OIDC to push/re-tag images.
  Trust scoped to `main`, `release/*`, and `v*.*.*`.
- `aws_iam_role.tf_plan` — **read-only**, assumable only from `pull_request`.
- `aws_iam_role.tf_apply` — read/write, assumable only from `main`.
- `aws_iam_policy.pull` — reusable read-only pull policy for EKS nodes or IRSA
- `aws_iam_openid_connect_provider.github` — only when
  `create_github_oidc_provider = true`

> `tf_apply` can manage IAM under the `backend-api-*` prefix, which includes its
> own role. That is unavoidable when Terraform manages its own CI role, but it
> means write access to `main` is effectively IAM-admin over that prefix. Keep
> `main` protected.

## Prerequisites

- Terraform **>= 1.11** (for S3 native state locking via `use_lockfile`)
- AWS credentials with rights to create ECR + IAM resources (bootstrap only)

## State

State lives in S3 — `edx-backtage-tfstate-724772096574`, key
`backend-api/ecr/terraform.tfstate` — with versioning, AES256, public access
blocked, and **native S3 locking** (no DynamoDB table). See the `backend` block
in `versions.tf`.

`terraform.tfvars` **is committed on purpose**. It holds no secrets, and CI needs
it: `github_owner`/`github_repo` have no defaults, and
`create_github_oidc_provider` must stay `false` because the provider already
exists in this account. Never put secrets in it.

## Normal workflow: through GitHub Actions

Terraform runs in CI, not from a laptop:

- **PR touching `terraform/**`** → `terraform.yml` runs `plan` with the
  read-only role and posts the plan as a PR comment.
- **Merge to `main`** → the same workflow runs `apply` with the write role.

Plan runs with `-lock=false`, since the plan role has no write access to the
state bucket.

## Bootstrap (first time only)

Only needed to create the roles CI later assumes — chicken-and-egg:

```bash
cd terraform
terraform init
terraform plan -out plan.out
terraform apply plan.out
```

## Wiring the outputs

```bash
terraform output -raw repository_url             # <account>.dkr.ecr.<region>.amazonaws.com/backend-api
terraform output -raw github_push_role_arn
terraform output -raw terraform_plan_role_arn
terraform output -raw terraform_apply_role_arn
terraform output -raw pull_policy_arn            # attach to EKS node role or IRSA role
```

Then set these repo **Variables** (Settings → Secrets and variables → Actions →
Variables — not Secrets; none are sensitive):

| Variable | Source |
| --- | --- |
| `AWS_REGION` | `us-east-1` |
| `TF_PLAN_ROLE_ARN` | `terraform_plan_role_arn` |
| `TF_APPLY_ROLE_ARN` | `terraform_apply_role_arn` |

`ECR_REGISTRY`, `ECR_REPOSITORY` and `AWS_ROLE_TO_ASSUME` are no longer read by
any workflow — see the note below.

## Notes

- **The ECR repository and the push role are orphaned.** They existed so CI
  could publish this repo's own Backstage image. Under Red Hat Developer Hub
  there is no image to build: the portal runs Red Hat's prebuilt image, pinned in
  `deploy/helm/rhdh/values.yaml`. Scaffolded services get their own registries
  from the Crossplane `ServiceRegistry` claim, not from this one. Nothing here
  was destroyed — confirm no service still pulls from it before you do.
- **The repository is named `backend-api`, not `backstage`.** This repo used to
  hold an Express notes API. Renaming means destroying and recreating the ECR
  repository, which `force_delete = false` blocks while images exist, so it was
  left as-is. Now that nothing pushes to it, deleting outright is the simpler
  option.
- Do **not** attach an `environment:` to the apply job without also adding the
  environment subject to `tf_apply_assume`. Attaching one rewrites the OIDC
  subject claim from `repo:OWNER/REPO:ref:refs/heads/main` to
  `repo:OWNER/REPO:environment:NAME`, and the role will refuse to be assumed.
- The `IMMUTABLE` tag policy means a scaffolded service's promotion cannot
  overwrite `latest`; each environment pins an explicit `image.tag` in the
  GitOps ledger.
- The OIDC thumbprint `6938fd4d98bab03faadb97b34396831e3780aea1` is GitHub's.
- Only one OIDC provider per URL per AWS account — hence
  `create_github_oidc_provider = false` here.
- **No RDS yet.** Staging and prod Helm values expect `externalPostgres.host`,
  but nothing here provisions that database.
