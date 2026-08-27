module "vpc" {
  source = "./modules/vpc"

  name               = "${local.name_prefix}-vpc"
  cidr_block         = var.vpc_cidr
  az_count           = var.az_count
  enable_nat_gateway = var.enable_nat_gateway
}

# Raw OSV snapshots land here, one prefix per hourly stamp, and are never mutated.
# The graph is rebuilt from this bucket, so it's the only piece of state that matters.
module "staging_bucket" {
  source = "./modules/s3-zone"

  bucket_name   = var.staging_bucket_name
  sse_algorithm = "AES256"
}
