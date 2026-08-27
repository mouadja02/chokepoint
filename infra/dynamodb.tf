# Content hash -> embedding, so re-ingesting an unchanged advisory costs zero Bedrock
# calls. refcount is what makes deletion safe: two advisories can share a chunk, and
# the vector only goes when the last reference does.
module "chunk_registry" {
  source = "./modules/dynamodb-table"

  table_name = "${local.name_prefix}-chunk-registry"
  hash_key   = "chunk_key"

  attributes = [
    { name = "chunk_key", type = "S" },
    { name = "advisory_id", type = "S" },
  ]

  # Withdrawing an advisory means finding every chunk it produced. Without this the
  # purge is a table scan.
  global_secondary_indexes = [
    {
      name     = "advisory_id-index"
      hash_key = "advisory_id"
    },
  ]
}

# One row per (snapshot, advisory) that actually changed. The graph can't answer
# what_changed() by itself -- a withdrawn advisory is deleted from it, so this is the
# only surviving record that it was ever there.
module "ingest_log" {
  source = "./modules/dynamodb-table"

  table_name = "${local.name_prefix}-ingest-log"
  hash_key   = "snapshot"
  range_key  = "advisory_id"

  attributes = [
    { name = "snapshot", type = "S" },
    { name = "advisory_id", type = "S" },
    { name = "ecosystem", type = "S" },
    { name = "applied_at", type = "S" },
  ]

  # what_changed(since) is a time range scan, not a per-snapshot lookup.
  global_secondary_indexes = [
    {
      name      = "applied_at-index"
      hash_key  = "ecosystem"
      range_key = "applied_at"
    },
  ]
}
