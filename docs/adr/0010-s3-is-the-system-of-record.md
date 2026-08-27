# 10. S3 snapshots are the system of record

Date: 2026-08-27
Status: Accepted

## Context

Something has to be the authoritative copy. The candidates are the graph, or the raw OSV
snapshots in S3.

The graph is memory-resident, expensive by the hour, and — by ADR-0004's cost logic — deleted
between work sessions. It's also derived: every node in it comes from a snapshot or a
lockfile.

OSV publishes the whole database as a daily-refreshed bulk export. A snapshot for a day that
has passed cannot be fetched back. That asymmetry decides it.

## Decision

`s3://chokepoint-data-staging/osv/raw/PyPI/<UTC hour>/` holds immutable snapshots, never
mutated, never deleted. The graph is derived and disposable. Any state that matters is either
in S3, or in the two DynamoDB tables, or it doesn't matter.

## Consequences

- The graph can be deleted at any moment with no loss, which is what makes the cost discipline
  in `runbook.md` viable rather than reckless.
- Rebuild-from-scratch is a daily operation, not a disaster recovery procedure, so it stays
  working. A recovery path exercised once a quarter is a recovery path that doesn't work.
- Every snapshot pair is a replayable delta. Twenty-five daily snapshots by the deadline is
  twenty-five days of real, unforced churn — the evidence base for the entire project, bought
  with one cron line.
- The delta suite can replay any historical transition through the real pipeline, because the
  inputs still exist byte-for-byte.
- Schema changes are rebuilds, not migrations. Nothing in this project needs migration code.
- Storage grows by roughly 35 MB a day and costs cents. The bucket is versioned; the snapshot
  prefixes are write-once, so versioning never accumulates.
- The one irrecoverable failure mode is a missed snapshot. Check weekly that the job is
  landing — a cron that stopped three days ago looks exactly like a quiet week.
