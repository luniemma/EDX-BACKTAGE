########################################
# EBS CSI driver
########################################
# Not optional here. This profile runs PostgreSQL inside the cluster to avoid
# an RDS instance, and that PostgreSQL wants a PersistentVolumeClaim. EKS ships
# no in-tree EBS provisioner any more, so without this addon the PVC sits
# Pending forever and RHDH never becomes ready — it waits on a database that
# cannot start.
#
# Declared as a standalone aws_eks_addon rather than inside the module's
# `addons` map on purpose: the addon needs an IAM role that is derived from the
# cluster's own OIDC provider, and feeding that back into the module's inputs
# is a dependency cycle.

data "aws_iam_policy_document" "ebs_csi_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

locals {
  oidc_host = replace(module.eks.cluster_oidc_issuer_url, "https://", "")
}

resource "aws_iam_role" "ebs_csi" {
  name               = "${var.name}-ebs-csi"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume.json
  description        = "IRSA role for the EBS CSI driver on ${var.name}"
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = module.eks.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = aws_iam_role.ebs_csi.arn

  # If a conflicting resource already exists, let the addon win rather than
  # failing the apply — there is no hand-installed driver here to preserve.
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  # The driver's controller has to land on a node, so the node group must be up.
  depends_on = [module.eks]
}
