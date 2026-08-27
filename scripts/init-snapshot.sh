#!/usr/bin/env bash
# Snapshot the OSV export for one ecosystem into S3. Run daily -- a day missed is a
# delta that can't be fetched back later.
set -euo pipefail

# The shell default profile points at the work account; this project is in the other one.
export AWS_PROFILE="${AWS_PROFILE_CHOKEPOINT:-default}"
# Git Bash rewrites leading-slash args into Windows paths and mangles the SSM name.
export MSYS_NO_PATHCONV=1

ECO="${ECO:-PyPI}"
BUCKET="${BUCKET:-$(aws ssm get-parameter --name /chokepoint/dev/staging_bucket \
  --query Parameter.Value --output text)}"

STAMP=$(date -u +%Y-%m-%dT%H)
BASE="https://storage.googleapis.com/osv-vulnerabilities/${ECO}"
DEST="s3://${BUCKET}/osv/raw/${ECO}/${STAMP}"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

curl -sfL "${BASE}/all.zip" -o "$tmp/all.zip"
aws s3 cp "$tmp/all.zip" "${DEST}/all.zip"

# modified_id.csv isn't part of a documented layout. If it goes away, diffing two
# consecutive all.zip snapshots carries the same information.
if curl -sfL "${BASE}/modified_id.csv" -o "$tmp/modified_id.csv"; then
    aws s3 cp "$tmp/modified_id.csv" "${DEST}/modified_id.csv"
else
    echo "no modified_id.csv for ${STAMP}" >&2
fi

echo "snapshot ${STAMP} -> ${DEST}"
