variable "env" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "env must be dev or prod."
  }
}

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name prefix used in resource naming"
  type        = string
  default     = "chokepoint"
}

variable "vpc_cidr" {
  description = "IPv4 CIDR block for the VPC. The subnet layout in modules/vpc assumes a /16."
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones to spread subnets across"
  type        = number
  default     = 2
}

# Off until something actually runs in a private subnet. A NAT gateway is ~$32/month
# plus data processing, which is most of the budget this project has.
variable "enable_nat_gateway" {
  description = "Create a NAT gateway for private subnet egress"
  type        = bool
  default     = false
}

# Created by hand on 26 Aug and imported; see imports.tf.
variable "staging_bucket_name" {
  description = "Name of the raw OSV snapshot bucket"
  type        = string
  default     = "chokepoint-data-staging"
}

variable "aws_profile" {
  description = "Local AWS credentials profile"
  type        = string
  default     = "default"
}

variable "aws_account_id" {
  description = "Account the config refuses to apply outside of"
  type        = string
  default     = "434740914108"
}
