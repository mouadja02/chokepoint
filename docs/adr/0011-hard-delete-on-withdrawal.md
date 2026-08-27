# 11. Hard delete on withdrawal, no tombstone

Date: 2026-08-27
Status: Accepted

## Context

An advisory can be withdrawn — retracted upstream as invalid. OSV marks this with a
`withdrawn` timestamp. It's rare (zero in the 27 August snapshot pair, a handful a year) and
it's the event the whole project is built around.

Three options for what the graph does:

1. **Hard delete.** Remove the node, its edges, its chunks, its vectors.
2. **Tombstone.** Keep the node, set `withdrawn_at`, delete only the `AFFECTED_BY` edges and
   the chunks. Exposure queries return nothing because there's no path, and history survives.
3. **Soft delete.** Keep everything, set `withdrawn_at`, filter on every read.

Option 3 is what most people reach for and it's the worst of the three: correctness now
depends on every query in every tool remembering a filter, forever.

## Decision

Hard delete. `Advisory.withdrawn_at` is not stored — the withdrawal is recorded in the ingest
log (ADR-0008) instead.

## Consequences

- The invariant is structural. An advisory that doesn't exist can't be returned by a query,
  including a query written carelessly at 1am. With a filter-based approach, one forgotten
  `WHERE` in one of five tools tells someone they're vulnerable when they aren't.
- The delta suite can assert `not graph.node_exists(ADVISORY)`, which is unambiguous and
  strictly stronger than asserting a flag.
- Deletion requires provenance on every derived edge and chunk, otherwise there's no way to
  find what the advisory produced. That requirement is now load-bearing, which is a feature —
  see `ontology.md`.
- History lives entirely in the ingest log and the S3 snapshots. "Was I ever affected by
  GHSA-x?" is not a graph query. That's a genuine loss and the reason to keep the log.
- Withdrawals are irreversible in the graph. If upstream un-withdraws an advisory — it happens
  — the record comes back through the normal `added` path on the next snapshot, which the
  pipeline already handles.

## Notes

Option 2 is defensible and worth being able to argue. A tombstone keeps `withdrawn_at`
readable, still returns no exposures because the edges are gone, and doesn't need the log for
the "was I ever" question. It was rejected because the delta suite's clearest assertion is
node non-existence, and because a tombstone is a node whose only purpose is to be filtered
out — which is soft delete wearing a different hat.

If this is revisited, `docs/schema.md` changes in the same commit. The failure mode to avoid
is a loader that deletes and a test that expects a tombstone.
