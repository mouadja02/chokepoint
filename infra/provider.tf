terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.52"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
  }
}

# This machine has credentials for two accounts and AWS_PROFILE often points at the
# other one. allowed_account_ids turns that into a failed plan instead of resources
# created in the wrong place.
provider "aws" {
  region              = var.aws_region
  profile             = var.aws_profile
  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = {
      project    = var.project_name
      env        = var.env
      managed_by = "terraform"
    }
  }
}
