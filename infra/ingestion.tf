# Stage 1 of the pipeline, on a schedule instead of on a laptop. It copies the OSV
# export into the staging bucket unmodified; nothing downstream of it exists yet.
module "snapshot" {
  source = "./modules/lambda-fn"

  name       = "${local.name_prefix}-osv-snapshot"
  source_dir = "${path.root}/../chokepoint/ingestion"
  handler    = "handler.handler"

  # ~34 MB streamed from GCS to S3. It runs in a couple of minutes on a bad day;
  # the timeout is there so a stalled connection fails instead of hanging.
  memory_size = 512
  timeout     = 300

  environment = {
    ECO          = "PyPI"
    BUCKET_PARAM = aws_ssm_parameter.staging_bucket.name
  }

  policy_json = data.aws_iam_policy_document.snapshot.json
}

data "aws_iam_policy_document" "snapshot" {
  # GetObject is for the HeadObject size check, not for reading a snapshot back.
  statement {
    actions   = ["s3:PutObject", "s3:GetObject", "s3:AbortMultipartUpload"]
    resources = ["${module.staging_bucket.bucket_arn}/osv/raw/*"]
  }

  statement {
    actions   = ["ssm:GetParameter"]
    resources = [aws_ssm_parameter.staging_bucket.arn]
  }
}
