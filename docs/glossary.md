# Glossary

Terse on purpose. Each entry says what it is and why you care here.

## Modeling

**Controlled vocabulary** — an agreed list of allowed values. `severity in {LOW, MODERATE,
HIGH, CRITICAL}`. No structure, just agreement.

**Taxonomy** — a vocabulary with one relation, usually "is a kind of". A tree.

**Ontology** — a vocabulary with many relations, plus rules about which combinations are
legal: what can connect to what, in which direction, how many times. In property-graph
practice it is the set of labels, relationship types, properties, their endpoints and
cardinalities. Nothing enforces it but your loader.

**Schema** — the ontology written down in a form something can check. In RDF that's
SHACL or OWL. Here it's `schema.md` plus loader assertions.

**Competency question** — a question the graph must be able to answer, written before
the model exists. The unit of design. See `ontology.md`.

**Instance data** — the actual nodes and edges. `fastapi@0.104.1` is instance data;
`Version` is ontology.

## Graph shapes

**LPG (labeled property graph)** — nodes and edges, each with a label and a bag of
key/value properties. Edges carry properties too. Neo4j, Neptune Analytics, TinkerPop.

**RDF** — everything is a triple `(subject, predicate, object)`, all identified by IRIs.
Edges cannot carry properties without extra machinery. Standardised, federatable, more
ceremony. See [ADR-0002](adr/0002-property-graph-over-rdf.md).

**Triple / quad** — RDF's unit of fact. A quad adds a named-graph slot, usually used for
provenance.

**IRI** — a global identifier, URL-shaped. RDF's node identity.

**PURL** — package URL, `pkg:pypi/fastapi@0.104.1`. The ecosystem's actual identifier
standard for a package or a version. Use it as your key even though you're not doing RDF.

**CPE** — the older NVD identifier format for products, `cpe:2.3:a:vendor:product:...`.
You'll meet it in advisory data. Messier than PURL; avoid keying on it.

**Reification** — turning a relationship into a node so it can have its own properties or
be pointed at. In an LPG you rarely need it, because edges already carry properties.

**Domain / range** — the allowed node label at the tail and head of an edge type.
`AFFECTED_BY: domain Version, range Advisory`.

**Cardinality** — how many of an edge are allowed per node. `Version -[:HAS_VERSION]-
Package` is many-to-one.

**Supernode** — a node with a huge degree, usually created by modeling a low-cardinality
attribute as a node. Every query that touches it fans out over its whole edge list.

**Traversal / hop / path** — following edges. One hop is one edge. A path is the sequence,
and returning the path is what "show me why" means here.

**Provenance** — the record of which input produced a given node or edge. Without it you
cannot delete correctly.

**Derived edge** — an edge you computed rather than read, e.g. `AFFECTED_BY` from a
version range. Every derived edge needs provenance.

**Bitemporal** — tracking both when a fact was true in the world (valid time) and when
your system learned it (transaction time). Overkill here; the ingest log covers it.

## Query languages

**openCypher** — the open specification of Neo4j's Cypher. `MATCH (a)-[:R]->(b) RETURN b`.
What Neptune Analytics speaks. See [ADR-0003](adr/0003-opencypher.md).

**Gremlin** — Apache TinkerPop's traversal language. Imperative step chaining,
`g.V().has(...).out(...)`. Neptune Database supports it; Neptune Analytics doesn't.

**SPARQL** — the query language for RDF. Pattern matching over triples, plus federation
across endpoints.

**GQL** — the ISO standard graph query language, published 2024, descended from Cypher.
The direction of travel. openCypher is the closest thing available today.

**MERGE** — Cypher's match-or-create. The idempotency primitive. Also the single largest
source of duplicate nodes, because `MERGE` on a full property bag matches nothing when
any one property differs. See `knowledge-graph.md`.

**Upsert** — insert or update, keyed. What every write in this project must be.

**Idempotent** — running it twice leaves the same state as running it once. Non-negotiable
here: the pipeline retries, and deltas get replayed.

## Vectors

**Embedding** — a fixed-length float vector standing in for a piece of text, such that
similar text lands nearby.

**Dimension** — the length of that vector. 1024 for Titan V2 by default. On Neptune
Analytics this is fixed when the graph is created and cannot be changed afterwards.

**Chunk** — a piece of text small enough to embed usefully. Here: a section of advisory
prose.

**Content hash / content-addressed** — naming a chunk by the hash of its text, so the same
text always resolves to the same key. This is what makes "re-embed only what changed"
possible.

**Refcount** — how many advisories currently reference a chunk. A vector may only be
deleted when this reaches zero.

**k-NN / ANN** — nearest-neighbour search, exact or approximate. What a vector index does.

**GraphRAG** — retrieval that mixes graph traversal with vector search. The point of the
project is knowing which one answers which question.

## AWS and domain

**m-NCU** — Neptune Analytics' capacity unit. One m-NCU is 1 GiB of memory plus matching
compute, billed by the hour while the graph exists. Smallest graph is 32. Read
`runbook.md` before you create one.

**OSV** — open source vulnerability database, and the JSON schema it publishes.
`osv.dev`. Free bulk export, no auth.

**GHSA / CVE** — advisory identifiers. GitHub's and MITRE's respectively. One advisory
often has both; OSV records aliases.

**CVSS** — the severity scoring vector and its numeric score. Gets revised, which is one
of your delta types.

**withdrawn** — an OSV field. Present means the advisory was retracted as invalid. Rare,
and the reason this project exists.

**SBOM** — software bill of materials. A file listing what's in a build. SPDX and
CycloneDX are the two formats.

**Lockfile** — the pinned, resolved dependency set for a project. Gives you exact
versions. Does not, by itself, give you the edges between them.

**Direct vs transitive** — you asked for `fastapi`; you got `anyio`. Transitive
dependencies are the whole reason a graph is needed.

**PEP 440** — Python's version ordering rules. Not semver. `1.0.post1 > 1.0`,
`1.0rc1 < 1.0`. Compare with a library, never with string comparison.
