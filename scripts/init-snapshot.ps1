# Snapshot the OSV export for one ecosystem into S3. Run daily -- a day missed is a
# delta that can't be fetched back later.
$ErrorActionPreference = "Stop"

# The shell default profile points at the work account; this project is in the other one.
if (-not $env:AWS_PROFILE_CHOKEPOINT) { $env:AWS_PROFILE = "default" }
else { $env:AWS_PROFILE = $env:AWS_PROFILE_CHOKEPOINT }

$ECO = if ($env:ECO) { $env:ECO } else { "PyPI" }
$BUCKET = if ($env:BUCKET) { $env:BUCKET } else {
    aws ssm get-parameter --name /chokepoint/dev/staging_bucket --query Parameter.Value --output text
}

$STAMP = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH")
$BASE = "https://storage.googleapis.com/osv-vulnerabilities/$ECO"
$DEST = "s3://$BUCKET/osv/raw/$ECO/$STAMP"

$tmp = Join-Path $env:TEMP "osv-$STAMP"
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

try {
    Invoke-WebRequest -Uri "$BASE/all.zip" -OutFile "$tmp/all.zip"
    aws s3 cp "$tmp/all.zip" "$DEST/all.zip"

    # modified_id.csv isn't part of a documented layout. If it goes away, diffing two
    # consecutive all.zip snapshots carries the same information.
    try {
        Invoke-WebRequest -Uri "$BASE/modified_id.csv" -OutFile "$tmp/modified_id.csv"
        aws s3 cp "$tmp/modified_id.csv" "$DEST/modified_id.csv"
    } catch {
        Write-Warning "no modified_id.csv for $STAMP"
    }
} finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

Write-Output "snapshot $STAMP -> $DEST"
