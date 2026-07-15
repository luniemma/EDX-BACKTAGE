data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  repo_arn   = "arn:${local.partition}:ecr:${var.aws_region}:${local.account_id}:repository/${var.repository_name}"
  github_subs = concat(
    [for b in var.github_push_branches : "repo:${var.github_owner}/${var.github_repo}:ref:refs/heads/${b}"],
    [for t in var.github_push_tags : "repo:${var.github_owner}/${var.github_repo}:ref:refs/tags/${t}"],
  )
}

########################################
# ECR repository
########################################

resource "aws_ecr_repository" "this" {
  name                 = var.repository_name
  image_tag_mutability = var.image_tag_mutability
  force_delete         = false

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after ${var.untagged_image_expire_days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_image_expire_days
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep last ${var.keep_last_release_images} release (v*) images"
        selection = {
          tagStatus      = "tagged"
          tagPatternList = ["v*"]
          countType      = "imageCountMoreThan"
          countNumber    = var.keep_last_release_images
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 3
        description  = "Keep last ${var.keep_last_sha_images} dev sha-* images"
        selection = {
          tagStatus      = "tagged"
          tagPatternList = ["sha-*"]
          countType      = "imageCountMoreThan"
          countNumber    = var.keep_last_sha_images
        }
        action = { type = "expire" }
      },
    ]
  })
}

resource "aws_ecr_repository_policy" "cross_account_pull" {
  count      = length(var.additional_pull_account_ids) > 0 ? 1 : 0
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCrossAccountPull"
        Effect = "Allow"
        Principal = {
          AWS = [for id in var.additional_pull_account_ids : "arn:${local.partition}:iam::${id}:root"]
        }
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:DescribeImages",
          "ecr:DescribeRepositories",
        ]
      },
    ]
  })
}

########################################
# GitHub Actions OIDC push role
########################################

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  github_oidc_arn = var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}

data "aws_iam_policy_document" "github_push_assume" {
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
      values   = local.github_subs
    }
  }
}

data "aws_iam_policy_document" "github_push" {
  statement {
    sid       = "GetAuthToken"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "PushPull"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:DescribeRepositories",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
      # Promotion workflow re-tags an existing image
      "ecr:BatchDeleteImage",
      "ecr:ListImages",
      "ecr:PutImageTagMutability",
    ]
    resources = [local.repo_arn]
  }
}

resource "aws_iam_role" "github_push" {
  name               = "${var.repository_name}-gha-push"
  assume_role_policy = data.aws_iam_policy_document.github_push_assume.json
  description        = "Assumed by GitHub Actions via OIDC to push/re-tag ${var.repository_name} images"
}

resource "aws_iam_role_policy" "github_push" {
  name   = "${var.repository_name}-gha-push"
  role   = aws_iam_role.github_push.id
  policy = data.aws_iam_policy_document.github_push.json
}

########################################
# EKS/K8s pull role (optional; for IRSA)
########################################
# Same-account EKS clusters can typically pull via the node IAM role's
# AmazonEC2ContainerRegistryReadOnly managed policy — no extra role needed.
# The role below is a *reusable* pull policy that can be attached to an
# IRSA-enabled ServiceAccount if you'd rather not grant node-wide access.

data "aws_iam_policy_document" "pull" {
  statement {
    sid       = "GetAuthToken"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "Pull"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:DescribeImages",
      "ecr:DescribeRepositories",
      "ecr:GetDownloadUrlForLayer",
      "ecr:ListImages",
    ]
    resources = [local.repo_arn]
  }
}

resource "aws_iam_policy" "pull" {
  name        = "${var.repository_name}-pull"
  description = "Read-only pull access for ${var.repository_name}"
  policy      = data.aws_iam_policy_document.pull.json
}
