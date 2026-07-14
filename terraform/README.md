# Terraform — ECR + GitHub OIDC push role

Provisions the container registry that CI/CD pushes into and Kubernetes pulls from.

## What gets created

- `aws_ecr_repository.this` — the registry itself
  - `IMMUTABLE` tags (production hygiene: `v1.2.3` never gets overwritten)
  - `scan_on_push = true` (Amazon Inspector native scanning)
  - AES256 encryption at rest
- `aws_ecr_lifecycle_policy.this` — expire untagged after 7d, keep last 30 `v*` and last 50 `sha-*` images
- `aws_iam_openid_connect_provider.github` — GitHub Actions OIDC federation (skip via `create_github_oidc_provider = false` if it already exists)
- `aws_iam_role.github_push` — role GitHub Actions assumes via OIDC to push/re-tag images. Trust policy is scoped to `main`, `release/*` branches and `v*.*.*` tags by default.
- `aws_iam_policy.pull` — reusable read-only pull policy for EKS nodes or IRSA service accounts
- `aws_ecr_repository_policy.cross_account_pull` — created only if `additional_pull_account_ids` is set

## Prerequisites

- Terraform >= 1.6
- AWS credentials with rights to create ECR + IAM resources
- (Recommended) A remote state backend — S3 + DynamoDB stanza is commented in `versions.tf`

## Bootstrap

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars — set github_owner, github_repo

terraform init
terraform plan -out plan.out
terraform apply plan.out
```

## Wiring the outputs

After `terraform apply`, grab the outputs:

```bash
terraform output -raw repository_url        # e.g. 123456789012.dkr.ecr.us-east-1.amazonaws.com/backend-api
terraform output -raw github_push_role_arn  # e.g. arn:aws:iam::123456789012:role/backend-api-gha-push
terraform output -raw pull_policy_arn       # attach to EKS node role or IRSA role
```

Then update:

1. **GitHub Actions** — add these repo variables (Settings → Secrets and variables → Actions → Variables):
   - `AWS_REGION` → `us-east-1` (or your region)
   - `ECR_REGISTRY` → the account portion of `repository_url`, e.g. `123456789012.dkr.ecr.us-east-1.amazonaws.com`
   - `ECR_REPOSITORY` → `backend-api`
   - `AWS_ROLE_TO_ASSUME` → the value of `github_push_role_arn`

2. **Helm** — set `image.repository` in `deploy/helm/backend-api/values.yaml` to the `repository_url` output.

3. **EKS pull** — attach the `pull_policy_arn` output to your node group's IAM role (or to an IRSA role referenced from `serviceAccount.annotations["eks.amazonaws.com/role-arn"]`).

## Notes

- The `IMMUTABLE` tag policy means the promotion workflow **cannot** overwrite `latest`. It uses digest-pinned promotion instead: prod's Helm values reference `image.tag = "v1.2.3"` and the release workflow only ever pushes tags matching the semver.
- The OIDC thumbprint `6938fd4d98bab03faadb97b34396831e3780aea1` is GitHub's — rotate if GitHub rotates theirs (rare, announced in advance).
- Only one OIDC provider per URL is allowed per AWS account. If another Terraform stack already created it, set `create_github_oidc_provider = false` and this stack will look it up instead.
