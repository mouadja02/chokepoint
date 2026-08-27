variable "name" {
  description = "Name prefix for the VPC and all network resources"
  type        = string
}

variable "cidr_block" {
  description = "IPv4 CIDR block for the VPC. Subnet layout assumes a /16 (public /24 and private /20 per AZ)."
  type        = string
}

variable "az_count" {
  description = "Number of availability zones to spread subnets across"
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 1 && var.az_count <= 3
    error_message = "az_count must be between 1 and 3."
  }
}

variable "enable_nat_gateway" {
  description = "Create a single shared NAT gateway for private subnet egress"
  type        = bool
  default     = true
}
