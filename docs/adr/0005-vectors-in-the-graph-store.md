# 5. Vectors in the graph store, not a separate index

Date: 2026-08-27
Status: Accepted

## Context

The agent needs vector search over advisory prose ("is this exploitable without
authentication?") alongside graph traversal. The vectors can live in the graph engine's own
index, or in a separate service — OpenSearch, pgvector, Pinecone, S3 Vectors.

Separate stores mean two systems that must agree about which chunks exist. Every withdrawal
becomes a distributed delete across two services with no shared transaction.

## Decision

Use Neptune Analytics' native vector index. Vectors are attached to `Chunk` nodes in the same
graph.

## Consequences

- One system to keep consistent instead of two. A withdrawal is a graph traversal that finds
  the chunks and removes their vectors in the same engine.
- k-NN composes with traversal in one query: retrieve similar chunks, then filter to
  advisories that affect a version this repo actually depends on. That composition is the
  whole argument for GraphRAG, and across two stores it's two round trips and a join in
  application code.
- Vector lifecycle is tied to graph lifecycle — including that deleting the graph to save
  money deletes the vectors. Mitigated by the chunk registry (ADR-0007), which holds the
  embeddings so a rebuild doesn't re-pay Bedrock.
- **Vector writes are not atomic or isolated.** They become durable and visible immediately,
  even if the surrounding query fails; graph mutations in the same query roll back and the
  vector write doesn't. Every write must be `MATCH`-then-upsert, retry-safe, and unchained
  from graph mutations. This is a real cost of the decision, not a footnote.
- One index per graph, dimension fixed at creation (ADR-0006).
- No hybrid search, no BM25, no metadata filtering syntax, no rerankers. Filtering happens by
  traversing from the returned nodes, which is fine here and would not be fine for a
  general-purpose search product.
- If the vector index turns out to be inadequate, the fallback is a separate store and a
  consistency problem to solve. Cheap to discover early: build `search_advisories` before the
  agent.
