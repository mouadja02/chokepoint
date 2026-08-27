# 4. Neptune Analytics, not Neptune Database

Date: 2026-08-27
Status: Accepted

## Context

Both are Amazon Neptune. They're different products.

**Neptune Database** is a durable, transactional, multi-AZ graph database. openCypher,
Gremlin and SPARQL. Scales to high query rates, backups, replicas, the usual database
guarantees. No native vector index.

**Neptune Analytics** is a memory-resident analytics engine. openCypher only. Built-in graph
algorithms and a **native vector index with k-NN inside openCypher queries**. Billed by
provisioned memory (m-NCU) by the hour, for as long as the graph exists.

What this project needs: multi-hop traversal, vector similarity over advisory prose, and both
in one query — "find advisories similar to this description that also affect a version I
depend on". The graph is derived: it's rebuilt from immutable S3 snapshots and is disposable
by design.

## Decision

Neptune Analytics.

## Alternatives considered

**Neptune Database.** Durability we don't need — the graph is derived, and losing it costs a
few minutes of rebuild. It has no vector index, so retrieval would need a second store
(ADR-0005). It's the right answer for a system of record; this graph isn't one.

**Neo4j Aura.** Better tooling, better documentation, native vector index, and a mature
ecosystem. Rejected because the project's stated context is AWS-native — Bedrock, AgentCore,
Step Functions — and because the point is to demonstrate this stack.

**PostgreSQL with pgvector and recursive CTEs.** Genuinely viable, and much cheaper. A
recursive CTE does transitive closure; pgvector does k-NN. The reason not to: `explain_path`
in SQL is a recursive CTE that nobody reads, the whole premise is demonstrating when a graph
is the right instrument, and a project arguing that graphs matter which is implemented in
Postgres argues the opposite. Worth being able to state this trade-off out loud — it's the
strongest challenge to the architecture, and "the graph earned its cost" is exactly what the
baseline harness in `evaluation.md` is there to prove.

## Consequences

- Traversal and vector search in one openCypher query, one store, one consistency story.
- **Cost is the dominant constraint.** Billing is by provisioned memory per hour, minimum 32
  m-NCU, which at the rate implied by the pricing page's own example is around $0.96/hour.
  Leaving a graph running for a month is roughly €700. See `runbook.md`.
- That constraint forces the graph to be deleted between sessions, which forces the pipeline
  to be genuinely reconstructible. The cost discipline and the architectural property are the
  same thing, which is a good argument and also a real risk if the rebuild ever breaks.
- openCypher only. No Gremlin, no SPARQL — consistent with ADR-0002 and ADR-0003.
- Vector index dimension is fixed at graph creation and can't be changed. See ADR-0006.
- Vector writes are not atomic and not isolated with respect to graph writes. This is the
  single most consequential technical constraint in the project and it shapes every delta
  operation — see `deltas.md`.
- No multi-AZ, no automatic failover. Irrelevant for a graph that's deleted nightly.
