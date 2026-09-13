########################################
# Alerts
########################################
# One SNS topic every platform alarm publishes to, the KMS key that encrypts
# it, the email subscriptions, a monthly cost budget, and the node alarms.
#
# The topic, its key and the budget live in this root beside the CI roles, for
# the same reason those do: destroy.yml tears the cluster down with a targeted
# destroy naming module.eks and module.vpc, so they survive a routine teardown.
# The budget is most useful exactly when nothing is supposed to be running.
# The node alarms are the exception and are targeted alongside the cluster —
# they watch the node group and mean nothing without it.

########## encryption ##########
# A customer-managed key rather than alias/aws/sns. CloudWatch cannot publish
# to a topic encrypted with the AWS-managed SNS key, whose key policy cannot
# be changed to admit cloudwatch.amazonaws.com, and the failure is silent: the
# alarm changes state and the notification never arrives. It costs about $1/month.

data "aws_iam_policy_document" "alerts_kms" {
  statement {
    sid       = "AccountAdministersKey"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
  }

  statement {
    sid       = "CloudWatchPublishesToEncryptedTopic"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey*"]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_kms_key" "alerts" {
  description             = "Encrypts the ${var.name} alerts SNS topic"
  enable_key_rotation     = true
  deletion_window_in_days = var.alerts_kms_deletion_window_days
  policy                  = data.aws_iam_policy_document.alerts_kms.json
}

resource "aws_kms_alias" "alerts" {
  name          = "alias/${var.name}-alerts"
  target_key_id = aws_kms_key.alerts.key_id
}

########## topic ##########

resource "aws_sns_topic" "alerts" {
  name              = "${var.name}-alerts"
  kms_master_key_id = aws_kms_key.alerts.arn
}

data "aws_iam_policy_document" "alerts_topic" {
  statement {
    sid    = "AccountManagesTopic"
    effect = "Allow"
    actions = [
      "SNS:AddPermission",
      "SNS:DeleteTopic",
      "SNS:GetTopicAttributes",
      "SNS:ListSubscriptionsByTopic",
      "SNS:Publish",
      "SNS:RemovePermission",
      "SNS:SetTopicAttributes",
      "SNS:Subscribe",
    ]
    resources = [aws_sns_topic.alerts.arn]

    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
  }

  # The confused-deputy guard CloudWatch documents: only alarms in this
  # account, and only alarms named for this platform, may publish.
  statement {
    sid       = "PlatformAlarmsPublish"
    effect    = "Allow"
    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.alerts.arn]

    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${local.partition}:cloudwatch:${var.aws_region}:${local.account_id}:alarm:${var.name}-*"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_sns_topic_policy" "alerts" {
  arn    = aws_sns_topic.alerts.arn
  policy = data.aws_iam_policy_document.alerts_topic.json
}

# Email subscriptions start as "pending confirmation". AWS mails each address
# a link and delivers nothing until it is followed — Terraform cannot do that
# step, so a fresh address is silent until its owner clicks.
resource "aws_sns_topic_subscription" "email" {
  for_each = toset(var.alert_emails)

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

########## cost ##########
# The whole account rather than a tag filter. Filtering on the Project tag
# only works once that tag is activated as a cost allocation tag in Billing,
# and until it is, a filtered budget tracks nothing and never fires.
#
# Budgets mails alert_emails directly instead of going through the topic:
# publishing to an encrypted topic would need budgets.amazonaws.com admitted to
# both the topic policy and the key policy, for no gain.

resource "aws_budgets_budget" "monthly" {
  name         = "${var.name}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  dynamic "notification" {
    for_each = length(var.alert_emails) > 0 ? var.budget_notifications : []

    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value.threshold_percent
      threshold_type             = "PERCENTAGE"
      notification_type          = notification.value.notification_type
      subscriber_email_addresses = var.alert_emails
    }
  }
}

########## node alarms ##########
# EC2 publishes instance metrics aggregated by Auto Scaling group on basic
# monitoring as well as detailed, and status checks at no charge, so these
# need no agent and no Container Insights.

locals {
  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = var.notify_on_recovery ? [aws_sns_topic.alerts.arn] : []
}

resource "aws_cloudwatch_metric_alarm" "nodes" {
  for_each = var.node_alarms

  alarm_name          = "${var.name}-nodes-${each.key}"
  alarm_description   = each.value.description
  namespace           = each.value.namespace
  metric_name         = each.value.metric_name
  statistic           = each.value.statistic
  comparison_operator = each.value.comparison_operator
  threshold           = each.value.threshold
  period              = each.value.period
  evaluation_periods  = each.value.evaluation_periods
  treat_missing_data  = each.value.treat_missing_data

  # one() fails the apply if a second node group ever appears, rather than
  # quietly watching only the first.
  dimensions = {
    AutoScalingGroupName = one(module.eks.eks_managed_node_groups_autoscaling_group_names)
  }

  alarm_actions = local.alarm_actions
  ok_actions    = local.ok_actions
}
