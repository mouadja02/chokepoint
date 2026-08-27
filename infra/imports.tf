# The staging bucket is adopted, never created: it holds the daily OSV snapshots,
# and those can't be re-fetched for a day that has passed. Keeping the import block
# means a lost state file re-adopts the bucket instead of trying to recreate it.
import {
  to = module.staging_bucket.aws_s3_bucket.this
  id = var.staging_bucket_name
}
