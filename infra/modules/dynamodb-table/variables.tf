variable "table_name" {
  description = "Name of the DynamoDB table"
  type        = string
}

variable "hash_key" {
  description = "Partition key attribute name"
  type        = string
}

variable "range_key" {
  description = "Sort key attribute name (null = simple primary key)"
  type        = string
  default     = null
}

variable "attributes" {
  description = "Key attributes used by the table and its indexes"
  type = list(object({
    name = string
    type = string
  }))
}

variable "billing_mode" {
  description = "PAY_PER_REQUEST (on-demand) or PROVISIONED"
  type        = string
  default     = "PAY_PER_REQUEST"
}

variable "global_secondary_indexes" {
  description = "Global secondary indexes"
  type = list(object({
    name               = string
    hash_key           = string
    range_key          = optional(string)
    projection_type    = optional(string, "ALL")
    non_key_attributes = optional(list(string))
  }))
  default = []
}

variable "ttl_attribute" {
  description = "Attribute holding the expiry epoch (null = TTL disabled)"
  type        = string
  default     = null
}

variable "stream_view_type" {
  description = "Stream view type (e.g. NEW_AND_OLD_IMAGES); null = stream disabled"
  type        = string
  default     = null
}

variable "point_in_time_recovery" {
  description = "Enable point-in-time recovery"
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Protect the table from deletion"
  type        = bool
  default     = false
}

variable "kms_key_arn" {
  description = "Customer-managed KMS key for encryption at rest (null = AWS-owned key)"
  type        = string
  default     = null
}

variable "alarm_actions" {
  description = "ARNs notified when a standard alarm fires (empty = alarm only)"
  type        = list(string)
  default     = []
}
