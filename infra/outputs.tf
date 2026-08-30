output "vpc_id" {
  value = module.vpc.vpc_id
}

output "private_subnet_ids" {
  value = module.vpc.private_subnet_ids
}

output "staging_bucket" {
  value = module.staging_bucket.bucket_id
}

output "chunk_registry_table" {
  value = module.chunk_registry.table_name
}

output "ingest_log_table" {
  value = module.ingest_log.table_name
}

output "snapshot_function" {
  value = module.snapshot.function_name
}
