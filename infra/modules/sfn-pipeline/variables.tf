variable "name" {
  description = "Name of the state machine"
  type        = string
}

variable "definition" {
  description = "Amazon States Language definition (JSON string, typically from templatefile)"
  type        = string
}

variable "type" {
  description = "STANDARD or EXPRESS"
  type        = string
  default     = "STANDARD"
}

variable "invoke_lambda_arns" {
  description = "Lambda function ARNs the state machine may invoke"
  type        = list(string)
  default     = []
}

variable "additional_policy_json" {
  description = "Extra IAM policy JSON for non-Lambda states (null = none)"
  type        = string
  default     = null
}

variable "log_level" {
  description = "Execution logging level: ALL, ERROR, FATAL or OFF"
  type        = string
  default     = "ERROR"
}

variable "include_execution_data" {
  description = "Include execution input/output in the logs"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention period in days"
  type        = number
  default     = 14
}

variable "alarm_actions" {
  description = "ARNs notified when a standard alarm fires (empty = alarm only)"
  type        = list(string)
  default     = []
}

variable "trigger" {
  description = "Optional EventBridge trigger: exactly one of schedule_expression or event_pattern"
  type = object({
    schedule_expression = optional(string)
    event_pattern       = optional(string)
    input               = optional(string)
  })
  default = null

  validation {
    condition     = var.trigger == null ? true : (var.trigger.schedule_expression == null) != (var.trigger.event_pattern == null)
    error_message = "trigger must set exactly one of schedule_expression or event_pattern."
  }
}
