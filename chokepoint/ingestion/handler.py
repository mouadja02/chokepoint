# Stage 1, acquire: the OSV export copied into S3 byte for byte. Nothing here parses a
# record -- S3 is the system of record and every later stage rebuilds from these objects.
#
# Same key layout as scripts/init-snapshot.*, which stays around as the manual catch-up
# path. A day missed is a delta that can't be fetched back later.

import logging
import os
import urllib.error
import urllib.request
from datetime import datetime, timezone

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client("s3")

ECO = os.environ.get("ECO", "PyPI")
BASE = f"https://storage.googleapis.com/osv-vulnerabilities/{ECO}"

# Resolved once per cold start, not baked into the deployment package: a bucket rename
# is a terraform apply, not a redeploy.
BUCKET = boto3.client("ssm").get_parameter(Name=os.environ["BUCKET_PARAM"])["Parameter"]["Value"]


def copy(name, prefix):
    """Stream one export file straight to S3 and return its size."""
    key = f"{prefix}/{name}"
    with urllib.request.urlopen(f"{BASE}/{name}", timeout=60) as resp:
        want = int(resp.headers["Content-Length"])
        s3.upload_fileobj(resp, BUCKET, key)

    # A truncated body doesn't always raise, and a short snapshot is worse than a
    # missing one -- it looks like 20,000 advisories were withdrawn overnight.
    got = s3.head_object(Bucket=BUCKET, Key=key)["ContentLength"]
    if got != want:
        raise RuntimeError(f"{key}: stored {got} bytes, upstream said {want}")

    logger.info("%s -> s3://%s/%s (%d bytes)", name, BUCKET, key, got)
    return got


def handler(event, context):
    stamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H")
    prefix = f"osv/raw/{ECO}/{stamp}"

    copy("all.zip", prefix)

    # modified_id.csv isn't part of a documented layout. If it goes away, diffing two
    # consecutive all.zip snapshots carries the same information.
    try:
        copy("modified_id.csv", prefix)
    except urllib.error.HTTPError as e:
        logger.warning("no modified_id.csv for %s (%s)", stamp, e)

    return {"snapshot": stamp, "prefix": f"s3://{BUCKET}/{prefix}"}
