# 12. Snapshot diff is the delta source

Date: 2026-08-27
Status: Accepted

## Context

Three ways to learn what changed in OSV:

- **Poll the API** for records modified since a timestamp.
- **Read `modified_id.csv`**, the export's own change feed.
- **Diff two full snapshots** taken a day apart.

The first two are cheaper. The third is the only one that lets you replay a transition after
the fact, because it keeps both sides of the diff.

Two things learned from the first snapshots: `modified_id.csv` is keyed on
`(modified_timestamp, id)`, so a line-by-line diff reports 18 added and 14 removed for a day
that actually had 4 additions and 14 modifications. And `modified_at` moving doesn't mean
anything meaningful changed — republished records bump it.

## Decision

Diff consecutive full snapshots, keyed on advisory id. Use `modified_at` as a cheap
pre-filter, then compare the fields that matter to classify. Treat `modified_id.csv` as a hint
only, parsed on the id column, and don't depend on it — it isn't part of a documented layout
and could disappear.

## Consequences

- Any two snapshots make a replayable delta, including pairs from before the delta engine
  existed. Twenty-five snapshots is a large, real test corpus obtained for free.
- Classification compares field subtrees, so a republished record produces a `republished`
  no-op rather than a spurious re-embed of the whole corpus on OSV format-change day.
- Survives the change feed's layout changing or vanishing, since nothing depends on it.
- The diff is O(size of the export), not O(changes) — a few seconds over 25,000 records.
  Irrelevant at this scale, wrong at ten times it.
- Delta granularity is one day, not one hour. Fine here; the snapshot script can run more
  often if a demo needs finer resolution.
- A missed snapshot is an unrecoverable gap. See ADR-0010.
- The pipeline can't detect a change that upstream makes and reverts between two snapshots.
  Accepted: that transition arguably never happened as far as anyone downstream is concerned.
