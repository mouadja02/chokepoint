variable "rule_name" {
  description = "Name of the EventBridge rule"
  type        = string
}

variable "description" {
  description = "Human-readable description of the rule"
  type        = string
  default     = ""
}

variable "event_bus_name" {
  description = "Event bus the rule is attached to"
  type        = string
  default     = "default"
}

variable "schedule_expression" {
  description = "cron()/rate() expression; mutually exclusive with event_pattern"
  type        = string
  default     = "cron(0 0 * * ? *)" # Midnight

}


variable "enabled" {
  description = "Whether the rule is enabled"
  type        = bool
  default     = true
}

variable "targets" {
  description = "Targets invoked when the rule matches"
  type = list(object({
    target_id       = string
    arn             = string
    role_arn        = optional(string)
    input           = optional(string)
    input_path      = optional(string)
    dead_letter_arn = optional(string)
  }))
}
