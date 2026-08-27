# 7. Content-addressed chunks with a DynamoDB registry

Date: 2026-08-27
Status: Accepted

## Context

Advisories get edited. A description changes and the naive pipeline re-embeds every chunk of
every advisory it touched — which costs money, takes time, and hides whether the incremental
path works at all, because a full reindex always produces correct answers.

Chunks are also shared. Boilerplate remediation text repeats across advisories, so the same
text can belong to several of them. Deleting a chunk when one advisory is withdrawn would
break the others.

## Decision

Name every chunk by the hash of its content plus its embedding parameters:

    chunk_key = sha256(model_id | dim | normalizer_version | normalized_text)

Keep a DynamoDB table `chokepoint-dev-chunk-registry` keyed on `chunk_key`, holding the
embedding and the **set of advisory ids** that reference it. A GSI on `advisory_id` answers
"which chunks did this advisory produce".

Before embedding, look up the key. On a hit, skip Bedrock entirely.

## Consequences

- Re-ingesting an unchanged advisory makes zero Bedrock calls, which is an assertion in the
  delta suite rather than an aspiration. Nothing else in the test suite catches a pipeline
  that silently reindexes everything, because it still returns correct answers.
- Editing one sentence re-embeds exactly one chunk. Also an assertion.
- Deletion is safe. A vector is removed only when the last referencing advisory releases it.
- **`referenced_by` is a set, not a counter.** Deltas get replayed and Step Functions retries;
  at-least-once is the normal case. Adding an id to a set twice is a no-op, incrementing an
  integer twice is a leak that never releases the vector, and decrementing twice deletes one
  that's still in use.
- Embeddings survive the nightly graph teardown, so rebuilding is free of Bedrock cost. This
  is what makes the delete-the-graph cost discipline affordable.
- The hash covers model id and dimension, so a model change invalidates every key rather than
  silently mixing vector spaces.
- The registry is a second source of truth about which chunks exist, so it can drift from the
  graph. The orphan sweep exists for exactly this — see `deltas.md`.
- Normalisation is now load-bearing. Any change to whitespace or markdown handling changes
  every key and re-embeds the corpus, which is why `normalizer_version` is in the hash rather
  than implicit.
