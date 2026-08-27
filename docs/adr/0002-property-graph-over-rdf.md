# 2. Property graph, not RDF

Date: 2026-08-27
Status: Accepted

## Context

Two families of graph model, and picking one determines the query language, the tooling, and
how the ontology is written down.

**RDF** models everything as triples `(subject, predicate, object)` with IRIs for identity.
It's a W3C standard with a real formal grounding: OWL for ontologies, SHACL for validation,
SPARQL for querying, federation across endpoints, and reasoners that derive new facts from
rules. Edges can't carry properties without reification or RDF-star.

**Labeled property graphs** have nodes and edges that both carry a label and arbitrary
key/value properties. No standard formal semantics, no inference, no federation. Cypher,
Gremlin, and now ISO GQL.

The specific pressure in this project: `AFFECTED_BY` carries `introduced`, `fixed`,
`range_type` and `source_range`. Those are attributes *of the relationship*, and they're
load-bearing — narrowing a range is an edge deletion driven by those exact properties.

## Decision

Labeled property graph.

## Alternatives considered

**RDF + a triple store.** The formal machinery is genuinely better if you need it: SHACL
would validate the schema that our loader has to enforce by hand, and OWL would express
`DEPENDS_ON` transitivity declaratively. But an edge with four properties becomes a reified
node plus five triples, which triples the size of the model and makes `explain_path` — the
project's central query — a mess of intermediate nodes with no domain meaning. There's also
no managed AWS RDF store with a native vector index, which would split the retrieval story
across two systems (see ADR-0005).

**RDF-star.** Solves the edge-property problem cleanly. Support across stores is uneven and
the tooling is thinner. Not worth the risk on a three-week schedule.

## Consequences

- Edge properties are native. `AFFECTED_BY` stays an edge, and the model stays six labels
  wide.
- No inference. Transitive dependency closure is a variable-length pattern computed at query
  time. That's fine and arguably better for data that changes daily, but it means every
  traversal needs an explicit depth bound.
- No SHACL, no OWL, no constraints. The ontology is enforced by the loader and written down
  in `docs/schema.md`, and nothing checks that they agree except tests we write.
- No federation with other vulnerability data sources. Not needed here; would matter for a
  system that had to join across organisations.
- Identity is still borrowed from the standards world: PURLs and GHSA ids as node ids. The
  useful half of RDF's discipline without the ceremony.
- SPARQL is off the table, which decides most of ADR-0003.
