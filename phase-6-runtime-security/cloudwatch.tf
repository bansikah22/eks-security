# ── Metric filter: 403 Forbidden responses in EKS audit logs ──────────────────
# The transcript: "you suddenly have an increase in the number of HTTP forbidden
# or unauthorized responses" — this filter counts those in the audit log stream.
resource "aws_cloudwatch_log_metric_filter" "forbidden_responses" {
  name           = "${var.cluster_name}-403-forbidden"
  log_group_name = aws_cloudwatch_log_group.eks_control_plane.name

  # Matches EKS audit log entries where the API server returned 403
  pattern = "{ $.responseStatus.code = 403 }"

  metric_transformation {
    name      = "403ForbiddenCount"
    namespace = "EKSSecurityMetrics/${var.cluster_name}"
    value     = "1"
    unit      = "Count"
  }

  depends_on = [null_resource.eks_logging]
}

# ── Metric filter: unauthorized (401) responses ────────────────────────────────
resource "aws_cloudwatch_log_metric_filter" "unauthorized_responses" {
  name           = "${var.cluster_name}-401-unauthorized"
  log_group_name = aws_cloudwatch_log_group.eks_control_plane.name

  pattern = "{ $.responseStatus.code = 401 }"

  metric_transformation {
    name      = "401UnauthorizedCount"
    namespace = "EKSSecurityMetrics/${var.cluster_name}"
    value     = "1"
    unit      = "Count"
  }

  depends_on = [null_resource.eks_logging]
}

variable "alarm_sns_topic_arn" {
  description = "Optional SNS topic ARN for CloudWatch alarm notifications"
  type        = string
  default     = null
}

# ── Alarm: spike in 403 Forbidden responses ───────────────────────────────────
# Fires when 10+ forbidden responses are counted in any 5-minute window.
resource "aws_cloudwatch_metric_alarm" "forbidden_spike" {
  alarm_name          = "${var.cluster_name}-403-spike"
  alarm_description   = "Spike in EKS API 403 Forbidden responses — possible unauthorized access attempt"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "403ForbiddenCount"
  namespace           = "EKSSecurityMetrics/${var.cluster_name}"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_sns_topic_arn != null && var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []

  tags = {
    Phase   = "6"
    Purpose = "security-alarm"
  }
}

# ── Alarm: spike in 401 Unauthorized responses ────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "unauthorized_spike" {
  alarm_name          = "${var.cluster_name}-401-spike"
  alarm_description   = "Spike in EKS API 401 Unauthorized responses — possible credential brute-force or misconfiguration"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "401UnauthorizedCount"
  namespace           = "EKSSecurityMetrics/${var.cluster_name}"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_sns_topic_arn != null && var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []

  tags = {
    Phase   = "6"
    Purpose = "security-alarm"
  }
}

output "forbidden_alarm_name" {
  description = "CloudWatch alarm that fires on 403 Forbidden spikes in EKS audit logs"
  value       = aws_cloudwatch_metric_alarm.forbidden_spike.alarm_name
}
