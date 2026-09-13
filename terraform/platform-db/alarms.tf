########################################
# Alarms
########################################
# RDS publishes these metrics at no extra cost. The alarms go with the
# instance — destroying this root destroys them — and publish to the topic the
# platform root owns, which outlives both.

locals {
  # try(): until the platform root has been applied with its alerts, the
  # output does not exist. Planning should still work; the check below says
  # what that means.
  alerts_topic_arn = try(data.terraform_remote_state.platform.outputs.alerts_topic_arn, null)
}

check "alerts_topic_available" {
  assert {
    condition     = local.alerts_topic_arn != null
    error_message = "The platform root has no alerts_topic_arn output yet, so the database alarms would notify no one. Apply terraform/platform first."
  }
}

resource "aws_cloudwatch_metric_alarm" "db" {
  for_each = var.db_alarms

  alarm_name          = "${var.name}-db-${each.key}"
  alarm_description   = each.value.description
  namespace           = each.value.namespace
  metric_name         = each.value.metric_name
  statistic           = each.value.statistic
  comparison_operator = each.value.comparison_operator
  threshold           = each.value.threshold
  period              = each.value.period
  evaluation_periods  = each.value.evaluation_periods
  treat_missing_data  = each.value.treat_missing_data

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.this.identifier
  }

  alarm_actions = compact([local.alerts_topic_arn])
  ok_actions    = var.notify_on_recovery ? compact([local.alerts_topic_arn]) : []
}
