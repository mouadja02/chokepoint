resource "aws_cloudwatch_event_rule" "this" {
  name                = var.rule_name
  description         = var.description
  event_bus_name      = var.event_bus_name
  schedule_expression = var.schedule_expression
  state               = var.enabled ? "ENABLED" : "DISABLED"

  lifecycle {
    # CI's apply-settings step toggles detection rules between modes;
    # Terraform must not fight it (the deploy runs a refresh-only drift check).
    ignore_changes = [state]
  }
}

resource "aws_cloudwatch_event_target" "this" {
  for_each = { for t in var.targets : t.target_id => t }

  rule           = aws_cloudwatch_event_rule.this.name
  event_bus_name = var.event_bus_name
  target_id      = each.value.target_id
  arn            = each.value.arn
  role_arn       = each.value.role_arn
  input          = each.value.input
  input_path     = each.value.input_path

  dynamic "dead_letter_config" {
    for_each = each.value.dead_letter_arn != null ? [1] : []

    content {
      arn = each.value.dead_letter_arn
    }
  }
}
