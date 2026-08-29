########################################
# GitHub Actions role for this root
########################################
# The existing backend-api-tf-apply role cannot apply this configuration: it is
# scoped to ECR, IAM under "backend-api-*", and a single state key. Rather than
# widening that role — which would hand the ECR/CI pipeline the ability to
# delete a cluster — this root gets its own.
#
# Be clear-eyed about what this role is. Standing up a VPC and an EKS cluster
# needs ec2:* and eks:* over the region, plus the ability to create the IAM
# roles the cluster and its node group assume. That is, in practice,
# infrastructure-admin within us-east-1. The controls that make it acceptable:
#
#   * it is assumable only from refs/heads/main, never from a pull request;
#   * IAM writes are confined to the "edx-rhdh-*" name prefix;
#   * everything is region-locked to var.aws_region;
#   * it cannot touch the ECR root's state key, and that root's role cannot
#     touch this one's.
#
# Keep main protected. Write access to main is write access to this cluster.

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  github_oidc_arn = "arn:${local.partition}:iam::${local.account_id}:oidc-provider/token.actions.githubusercontent.com"

  platform_state_arns = [
    "arn:${local.partition}:s3:::${var.tfstate_bucket}/edx/platform/terraform.tfstate",
    "arn:${local.partition}:s3:::${var.tfstate_bucket}/edx/platform/terraform.tfstate.tflock",
    "arn:${local.partition}:s3:::${var.tfstate_bucket}/edx/platform-addons/terraform.tfstate",
    "arn:${local.partition}:s3:::${var.tfstate_bucket}/edx/platform-addons/terraform.tfstate.tflock",
  ]

  platform_managed_iam = [
    "arn:${local.partition}:iam::${local.account_id}:role/${var.name}-*",
    "arn:${local.partition}:iam::${local.account_id}:policy/${var.name}-*",
  ]
}

data "aws_iam_policy_document" "platform_apply_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Branch-pinned, not repo-pinned. A pull_request subject is deliberately
    # absent: nothing that can be opened by anyone should reach this role.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        for b in var.terraform_apply_branches :
        "repo:${var.github_owner}/${var.github_repo}:ref:refs/heads/${b}"
      ]
    }
  }
}

data "aws_iam_policy_document" "platform_apply" {
  # Networking and compute. Resource-level scoping is not meaningful for most
  # of these — you cannot name a VPC that does not exist yet — so the boundary
  # is the region instead.
  statement {
    sid    = "NetworkAndCompute"
    effect = "Allow"
    actions = [
      "ec2:*",
      "eks:*",
      "autoscaling:*",
      "elasticloadbalancing:*",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  # The EKS module creates a KMS key to encrypt Kubernetes Secrets at rest.
  statement {
    sid    = "KmsForSecretEncryption"
    effect = "Allow"
    actions = [
      "kms:CreateKey",
      "kms:CreateAlias",
      "kms:DeleteAlias",
      "kms:DescribeKey",
      "kms:EnableKeyRotation",
      "kms:GetKeyPolicy",
      "kms:GetKeyRotationStatus",
      "kms:ListAliases",
      "kms:ListResourceTags",
      "kms:PutKeyPolicy",
      "kms:ScheduleKeyDeletion",
      "kms:TagResource",
      "kms:UntagResource",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  statement {
    sid    = "ControlPlaneLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:DeleteLogGroup",
      "logs:DescribeLogGroups",
      "logs:PutRetentionPolicy",
      "logs:TagResource",
      "logs:UntagResource",
      "logs:ListTagsForResource",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  # IAM writes are name-prefixed. The cluster role, the node group role and the
  # EBS CSI IRSA role all start with var.name.
  statement {
    sid    = "ManageOwnedIam"
    effect = "Allow"
    actions = [
      "iam:AttachRolePolicy",
      "iam:CreateInstanceProfile",
      "iam:CreateOpenIDConnectProvider",
      "iam:CreatePolicy",
      "iam:CreatePolicyVersion",
      "iam:CreateRole",
      "iam:CreateServiceLinkedRole",
      "iam:DeleteInstanceProfile",
      "iam:DeleteOpenIDConnectProvider",
      "iam:DeletePolicy",
      "iam:DeletePolicyVersion",
      "iam:DeleteRole",
      "iam:DeleteRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePolicy",
      "iam:TagInstanceProfile",
      "iam:TagOpenIDConnectProvider",
      "iam:TagPolicy",
      "iam:TagRole",
      "iam:UntagPolicy",
      "iam:UntagRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:UpdateRole",
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
    ]
    resources = concat(local.platform_managed_iam, [
      "arn:${local.partition}:iam::${local.account_id}:instance-profile/${var.name}-*",
      "arn:${local.partition}:iam::${local.account_id}:oidc-provider/oidc.eks.${var.aws_region}.amazonaws.com/*",
    ])
  }

  # EKS hands the cluster and node group roles to the service; without
  # PassRole the create call fails even though the roles exist.
  statement {
    sid       = "PassClusterRoles"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = local.platform_managed_iam
  }

  statement {
    sid       = "ReadIam"
    effect    = "Allow"
    actions   = ["iam:Get*", "iam:List*"]
    resources = ["*"]
  }

  # This root's state, and the addons root's — the addons workflow runs under
  # the same role and reads this one's outputs.
  statement {
    sid    = "ReadWriteState"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = local.platform_state_arns
  }

  statement {
    sid       = "ListStateBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = ["arn:${local.partition}:s3:::${var.tfstate_bucket}"]
  }
}

resource "aws_iam_role" "platform_apply" {
  name               = "${var.name}-tf-apply"
  assume_role_policy = data.aws_iam_policy_document.platform_apply_assume.json
  description        = "Terraform apply role for the platform roots, ${join(", ", var.terraform_apply_branches)} only"
}

resource "aws_iam_role_policy" "platform_apply" {
  name   = "${var.name}-tf-apply"
  role   = aws_iam_role.platform_apply.id
  policy = data.aws_iam_policy_document.platform_apply.json
}

output "platform_apply_role_arn" {
  description = "Set this as the TF_PLATFORM_APPLY_ROLE_ARN repository variable."
  value       = aws_iam_role.platform_apply.arn
}
