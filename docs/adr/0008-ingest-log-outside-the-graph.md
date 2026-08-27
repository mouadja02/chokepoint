# 8. The ingest log lives outside the graph

Date: 2026-08-27
Status: Accepted

## Context

`what_changed(since)` has to report what happened between two points in time: added,
modified, withdrawn. The obvious place to answer that from is the graph.

It can't be. ADR-0011 deletes a withdrawn advisory outright, so the moment the interesting
event happens, the graph loses every trace that the advisory ever existed. The most valuable
delta to report is precisely the one the graph cannot report.

## Decision

A DynamoDB table `chokepoint-dev-ingest-log`, one row per `(snapshot, advisory_id)` that
actually changed, written after the graph and vector work succeeds. A GSI on
`(ecosystem, applied_at)` makes `what_changed(since)` a time range query.

## Consequences

- `what_changed` is answerable for withdrawals, which is the demo.
- It's a proper append-only event log: the graph holds current truth, the log holds
  transitions. Standard separation, and it keeps every graph query free of time filters.
- Rows carry a `detail` field — edges removed, chunks re-embedded — so the answer is "GHSA-x
  narrowed its range, one exposure removed" rather than a list of ids.
- Time range queries hit a GSI instead of scanning every snapshot partition.
- A second store to keep consistent with the graph. The log is written last, so a crash
  leaves a delta unapplied and unlogged, which is recoverable; the reverse would be a logged
  delta that never happened, which is a wrong answer with provenance attached.
- Answering "what did the graph look like on 14 September" needs a replay of the log over a
  base snapshot, not a query. Acceptable — nobody asks that question here — but it's the real
  cost of not keeping history in the graph.
- The log is also the audit trail for the project itself: how many deltas of each kind were
  applied over three weeks, which is a number worth reporting.
