########################################
# GitHub Actions OIDC roles for Terraform itself
########################################
# Two roles, deliberately split:
#
#   *-tf-plan   read-only, assumable from pull_request. A PR — including one
#               authored by anyone who can open one — can only ever read.
#   *-tf-apply  read/write, assumable only from the branches in
#               var.terraform_apply_branches (main by default).
#
# Note: tf-apply can manage IAM roles matching "${var.repository_name}-*",
# which includes itself. That is inherent in letting Terraform manage its own
# CI role, but it does mean write access to main is effectively IAM-admin over
# that name prefix. Keep main protected.

locals {
  tf_state_arn = "arn:${local.partition}:s3:::${var.tfstate_bucket}/${var.tfstate_key}"

  tf_apply_subs = [
    for b in var.terraform_apply_branches :
    "repo:${var.github_owner}/${var.github_repo}:ref:refs/heads/${b}"
  ]

  tf_managed_iam = [
    "arn:${local.partition}:iam::${local.account_id}:role/${var.repository_name}-*",
    "arn:${local.partition}:iam::${local.account_id}:policy/${var.repository_name}-*",
  ]
}

########## plan role (read-only, PRs) ##########

data "aws_iam_policy_document" "tf_plan_assume" {
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

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_owner}/${var.github_repo}:pull_request"]
    }
  }
}

data "aws_iam_policy_document" "tf_plan" {
  statement {
    sid    = "ReadInfra"
    effect = "Allow"
    actions = [
      "ecr:Describe*",
      "ecr:Get*",
      "ecr:List*",
      "iam:Get*",
      "iam:List*",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "ReadState"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = [local.tf_state_arn]
  }

  statement {
    sid       = "ListStateBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = ["arn:${local.partition}:s3:::${var.tfstate_bucket}"]
  }
}

resource "aws_iam_role" "tf_plan" {
  name               = "${var.repository_name}-tf-plan"
  assume_role_policy = data.aws_iam_policy_document.tf_plan_assume.json
  description        = "Read-only Terraform plan role for GitHub Actions PRs"
}

resource "aws_iam_role_policy" "tf_plan" {
  name   = "${var.repository_name}-tf-plan"
  role   = aws_iam_role.tf_plan.id
  policy = data.aws_iam_policy_document.tf_plan.json
}

########## apply role (read/write, main only) ##########

data "aws_iam_policy_document" "tf_apply_assume" {
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

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.tf_apply_subs
    }
  }
}

data "aws_iam_policy_document" "tf_apply" {
  statement {
    sid    = "ManageEcr"
    effect = "Allow"
    actions = [
      "ecr:CreateRepository",
      "ecr:DeleteRepository",
      "ecr:Describe*",
      "ecr:Get*",
      "ecr:List*",
      "ecr:PutImageScanningConfiguration",
      "ecr:PutImageTagMutability",
      "ecr:PutLifecyclePolicy",
      "ecr:DeleteLifecyclePolicy",
      "ecr:SetRepositoryPolicy",
      "ecr:DeleteRepositoryPolicy",
      "ecr:TagResource",
      "ecr:UntagResource",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ManageOwnedIam"
    effect = "Allow"
    actions = [
      "iam:AttachRolePolicy",
      "iam:CreatePolicy",
      "iam:CreatePolicyVersion",
      "iam:CreateRole",
      "iam:DeletePolicy",
      "iam:DeletePolicyVersion",
      "iam:DeleteRole",
      "iam:DeleteRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePolicy",
      "iam:TagPolicy",
      "iam:TagRole",
      "iam:UntagPolicy",
      "iam:UntagRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:UpdateRole",
    ]
    resources = local.tf_managed_iam
  }

  statement {
    sid       = "ReadIam"
    effect    = "Allow"
    actions   = ["iam:Get*", "iam:List*"]
    resources = ["*"]
  }

  statement {
    sid    = "ReadWriteState"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    # The second ARN is the native S3 lock file (use_lockfile = true).
    resources = [
      local.tf_state_arn,
      "${local.tf_state_arn}.tflock",
    ]
  }

  statement {
    sid       = "ListStateBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = ["arn:${local.partition}:s3:::${var.tfstate_bucket}"]
  }
}

resource "aws_iam_role" "tf_apply" {
  name               = "${var.repository_name}-tf-apply"
  assume_role_policy = data.aws_iam_policy_document.tf_apply_assume.json
  description        = "Terraform apply role for GitHub Actions on ${join(", ", var.terraform_apply_branches)}"
}

resource "aws_iam_role_policy" "tf_apply" {
  name   = "${var.repository_name}-tf-apply"
  role   = aws_iam_role.tf_apply.id
  policy = data.aws_iam_policy_document.tf_apply.json
}
