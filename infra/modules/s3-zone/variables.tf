variable "bucket_name" {
  description = "Globally unique S3 bucket name (must be lowercase)"
  type        = string
}

variable "versioning_enabled" {
  description = "Enable object versioning for recovery"
  type        = bool
  default     = true
}

variable "sse_algorithm" {
  description = "Server-side encryption algorithm: AES256 or aws:kms"
  type        = string
  default     = "AES256"
}

variable "kms_key_arn" {
  description = "Customer-managed KMS key ARN for SSE-KMS (only used when sse_algorithm is aws:kms; null falls back to the AWS-managed key)"
  type        = string
  default     = null
}
