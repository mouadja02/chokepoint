# 3. openCypher, not Gremlin or SPARQL

Date: 2026-08-27
Status: Accepted

## Context

Three query languages are plausible for a graph on AWS, and they aren't interchangeable —
each belongs to a different model, and the choice constrains the store as much as the store
constrains the choice.

**SPARQL** queries RDF. Declarative pattern matching over triples, plus property paths,
aggregation, and federation across remote endpoints. Standard, stable, well-specified.
Requires an RDF store.

**Gremlin** is Apache TinkerPop's traversal language: imperative step chaining,
`g.V().has('name','fastapi').out('DEPENDS_ON').until(...)`. Runs on many engines. Extremely
expressive for traversals that need explicit control over order, backtracking and side
effects. Reads like a program, not like a pattern.

**openCypher** is the open specification of Neo4j's Cypher. Declarative ASCII-art patterns:
`MATCH (a)-[:DEPENDS_ON*1..8]->(b)`. It's the basis of ISO GQL, published in 2024, so it's
where the standard is heading.

The queries this project actually needs: variable-length traversal returning whole paths,
filtering on edge properties, aggregation over paths, and a call into vector k-NN.

## Decision

openCypher.

## Alternatives considered

**SPARQL** was eliminated by ADR-0002. There's no RDF here, and no managed AWS RDF store with
a native vector index. If the domain had been "join our vulnerability data against three
external published datasets", this would be the right answer and the whole model would look
different.

**Gremlin** is a real option — Neptune Database supports it — and it would express
`best_upgrade` well, since that's an imperative search where controlling traversal order
matters. Against it: `explain_path` returns paths, and Cypher's `MATCH p = (...)  RETURN p`
is one line where Gremlin needs a path step plus projection. Gremlin's learning curve is
steeper for someone whose graph experience is new, and the debugging story is worse — a
mistyped step chain fails at runtime somewhere in the middle. It's also not supported on
Neptune Analytics at all (ADR-0004), so choosing it would mean choosing a different store.

The honest ordering: the store decision (ADR-0004) forces openCypher. This ADR records that
openCypher is also what we'd have chosen on the merits, so the constraint isn't costing us
anything.

## Consequences

- Patterns read like the data model. `(:Version)-[:AFFECTED_BY]->(:Advisory)` in a query is
  the same string as in `schema.md`, which keeps documentation and code honest.
- `MATCH p = ... RETURN p` returns whole paths, which is exactly `explain_path`.
- Neptune's vector search is exposed as openCypher procedures (`neptune.algo.vectors.*`), so
  graph traversal and k-NN compose in one query.
- Aligned with ISO GQL, so the skill transfers.
- No APOC, no user-defined procedures, no constraints, no declarable indexes. Neo4j habits
  and Stack Overflow answers will suggest all four.
- `MERGE` is the only idempotency primitive, and it's sharp — see `knowledge-graph.md`.
- Imperative traversals are awkward. If `best_upgrade` turns out to need real search control,
  it gets computed in Python over query results rather than in one clever query.
- Locked out of Gremlin-only tooling and of anything that speaks SPARQL.
