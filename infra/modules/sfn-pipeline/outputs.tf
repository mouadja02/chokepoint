output "state_machine_arn" {
  description = "ARN of the state machine"
  value       = aws_sfn_state_machine.this.arn
}

output "state_machine_name" {
  description = "Name of the state machine"
  value       = aws_sfn_state_machine.this.name
}

output "role_arn" {
  description = "ARN of the state machine execution role"
  value       = aws_iam_role.this.arn
}

output "log_group_name" {
  description = "Name of the vended-logs log group"
  value       = aws_cloudwatch_log_group.this.name
}

output "trigger_dlq_arn" {
  description = "ARN of the trigger delivery DLQ (null when no trigger)"
  value       = var.trigger != null ? aws_sqs_queue.trigger_dlq[0].arn : null
}
