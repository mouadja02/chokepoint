# Everything downstream (snapshot scripts, Lambdas, the rebuild job) reads names from
# here rather than hardcoding them, so a rename is a single apply.

resource "aws_ssm_parameter" "staging_bucket" {
  name  = "${local.ssm_prefix}/staging_bucket"
  type  = "String"
  value = module.staging_bucket.bucket_id
}

resource "aws_ssm_parameter" "vpc_id" {
  name  = "${local.ssm_prefix}/vpc_id"
  type  = "String"
  value = module.vpc.vpc_id
}

resource "aws_ssm_parameter" "private_subnet_ids" {
  name  = "${local.ssm_prefix}/private_subnet_ids"
  type  = "StringList"
  value = join(",", module.vpc.private_subnet_ids)
}

resource "aws_ssm_parameter" "chunk_registry_table" {
  name  = "${local.ssm_prefix}/chunk_registry_table"
  type  = "String"
  value = module.chunk_registry.table_name
}

resource "aws_ssm_parameter" "ingest_log_table" {
  name  = "${local.ssm_prefix}/ingest_log_table"
  type  = "String"
  value = module.ingest_log.table_name
}
