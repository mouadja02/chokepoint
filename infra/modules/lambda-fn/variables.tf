variable "name" {
  description = "Function name, also used for the role and the log group"
  type        = string
}

variable "source_dir" {
  description = "Directory zipped into the deployment package"
  type        = string
}

variable "handler" {
  description = "Entry point, module.function relative to the package root"
  type        = string
}

variable "runtime" {
  description = "Lambda runtime identifier"
  type        = string
  default     = "python3.13"
}

variable "memory_size" {
  description = "Memory in MB. Network throughput scales with it, so raise this before the timeout."
  type        = number
  default     = 512
}

variable "timeout" {
  description = "Timeout in seconds"
  type        = number
  default     = 60
}

variable "environment" {
  description = "Environment variables"
  type        = map(string)
  default     = {}
}

# Not optional, and not optional by accident: making it so would mean count-ing a
# resource on a value that is only known after the bucket exists.
variable "policy_json" {
  description = "Inline IAM policy for whatever the function touches beyond CloudWatch Logs"
  type        = string
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention"
  type        = number
  default     = 14
}
