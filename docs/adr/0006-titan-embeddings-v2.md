# 6. Titan Text Embeddings V2 at 1024 dimensions

Date: 2026-08-27
Status: Accepted — and the dimension is irreversible after graph creation

## Context

Advisory prose gets embedded for `search_advisories`. On Bedrock the practical options are
Amazon Titan Text Embeddings V2 (`amazon.titan-embed-text-v2:0`) and Cohere Embed.

Titan V2 emits 1024 (default), 512 or 256 dimensions, with an optional `normalize` flag
(default true) and float or binary output.

The binding constraint: **Neptune Analytics fixes the vector index dimension when the graph
is created, and it can't be changed.** Changing embedding model or dimension later means
deleting and rebuilding the graph.

## Decision

`amazon.titan-embed-text-v2:0`, 1024 dimensions, normalized.

## Consequences

- The graph is created with `dimension: 1024`. Every loader asserts this at startup, because
  loading embeddings into a graph with no vector index, or the wrong dimension, either fails
  with a `ParsingException` naming the line or — worse, with no index — succeeds while
  silently discarding the embeddings.
- Normalized vectors mean cosine similarity and dot product agree, so distance metric
  confusion can't produce subtly wrong rankings.
- The model id and dimension are part of `chunk_key` (ADR-0007). Switching models changes
  every key, so every chunk correctly re-embeds and no vectors from two different spaces ever
  coexist in one index.
- 512 or 256 would cut storage and memory roughly in half or a quarter, which matters on a
  memory-billed engine. At ~50,000 chunks the difference is not worth the retrieval quality
  risk. Revisit only if m-NCU pressure appears, and revisiting means a rebuild.
- Bedrock model access has to be enabled in the region before the first call. It's a console
  toggle and it's a five-minute surprise if you meet it on the day you're loading.
- Locked to Bedrock for embeddings. Fine — the project is deliberately AWS-native.
