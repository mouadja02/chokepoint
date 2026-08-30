# Vended log group — Step Functions requires the /aws/vendedlogs/ prefix
# to stay under the CloudWatch Logs resource-policy size limit.
resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/vendedlogs/states/${var.name}"
  retention_in_days = var.log_retention_days
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${var.name}-sfn-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

# Log-delivery permissions cannot be scoped to one log group — the CloudWatch
# Logs delivery API requires "*" (AWS limitation for vended logs).
data "aws_iam_policy_document" "logging" {
  statement {
    actions = [
      "logs:CreateLogDelivery",
      "logs:GetLogDelivery",
      "logs:UpdateLogDelivery",
      "logs:DeleteLogDelivery",
      "logs:ListLogDeliveries",
      "logs:PutResourcePolicy",
      "logs:DescribeResourcePolicies",
      "logs:DescribeLogGroups",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "logging" {
  name   = "${var.name}-logging"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.logging.json
}

data "aws_iam_policy_document" "invoke" {
  count = length(var.invoke_lambda_arns) > 0 ? 1 : 0

  statement {
    actions = ["lambda:InvokeFunction"]
    # Include the ":*" qualifier form so versioned/alias invocations work.
    resources = concat(var.invoke_lambda_arns, [for arn in var.invoke_lambda_arns : "${arn}:*"])
  }
}

resource "aws_iam_role_policy" "invoke" {
  count = length(var.invoke_lambda_arns) > 0 ? 1 : 0

  name   = "${var.name}-invoke-lambdas"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.invoke[0].json
}

resource "aws_iam_role_policy" "additional" {
  count = var.additional_policy_json != null ? 1 : 0

  name   = "${var.name}-additional"
  role   = aws_iam_role.this.id
  policy = var.additional_policy_json
}

resource "aws_sfn_state_machine" "this" {
  name       = var.name
  role_arn   = aws_iam_role.this.arn
  definition = var.definition
  type       = var.type

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.this.arn}:*"
    include_execution_data = var.include_execution_data
    level                  = var.log_level
  }

  depends_on = [aws_iam_role_policy.logging]
}

resource "aws_cloudwatch_metric_alarm" "failed" {
  alarm_name          = "${var.name}-failed"
  alarm_description   = "State machine ${var.name} has failed executions"
  namespace           = "AWS/States"
  metric_name         = "ExecutionsFailed"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_actions

  dimensions = {
    StateMachineArn = aws_sfn_state_machine.this.arn
  }
}

# --- Optional EventBridge trigger ---

resource "aws_cloudwatch_event_rule" "trigger" {
  count = var.trigger != null ? 1 : 0

  name                = "${var.name}-trigger"
  description         = "Starts ${var.name} executions"
  schedule_expression = var.trigger.schedule_expression
  event_pattern       = var.trigger.event_pattern
}

# Failed StartExecution deliveries land here instead of vanishing.
resource "aws_sqs_queue" "trigger_dlq" {
  count = var.trigger != null ? 1 : 0

  name                      = "${var.name}-trigger-dlq"
  message_retention_seconds = 1209600 # 14 days
}

data "aws_iam_policy_document" "trigger_dlq" {
  count = var.trigger != null ? 1 : 0

  statement {
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.trigger_dlq[0].arn]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudwatch_event_rule.trigger[0].arn]
    }
  }
}

resource "aws_sqs_queue_policy" "trigger_dlq" {
  count = var.trigger != null ? 1 : 0

  queue_url = aws_sqs_queue.trigger_dlq[0].id
  policy    = data.aws_iam_policy_document.trigger_dlq[0].json
}

data "aws_iam_policy_document" "events_assume_role" {
  count = var.trigger != null ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "trigger" {
  count = var.trigger != null ? 1 : 0

  name               = "${var.name}-trigger-role"
  assume_role_policy = data.aws_iam_policy_document.events_assume_role[0].json
}

data "aws_iam_policy_document" "start_execution" {
  count = var.trigger != null ? 1 : 0

  statement {
    actions   = ["states:StartExecution"]
    resources = [aws_sfn_state_machine.this.arn]
  }
}

resource "aws_iam_role_policy" "trigger" {
  count = var.trigger != null ? 1 : 0

  name   = "${var.name}-start-execution"
  role   = aws_iam_role.trigger[0].id
  policy = data.aws_iam_policy_document.start_execution[0].json
}

resource "aws_cloudwatch_event_target" "trigger" {
  count = var.trigger != null ? 1 : 0

  rule      = aws_cloudwatch_event_rule.trigger[0].name
  target_id = "${var.name}-sfn"
  arn       = aws_sfn_state_machine.this.arn
  role_arn  = aws_iam_role.trigger[0].arn
  input     = var.trigger.input

  dead_letter_config {
    arn = aws_sqs_queue.trigger_dlq[0].arn
  }
}
