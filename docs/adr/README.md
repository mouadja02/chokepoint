# Decisions

One file per decision, numbered, never edited after acceptance — superseded by a new one
instead. Nygard's format: context, decision, consequences. The consequences section is the
one that earns its keep; anyone can justify a choice, and the value is in having written down
what it costs before finding out.

    0001  Record architecture decisions
    0002  Property graph, not RDF
    0003  openCypher, not Gremlin or SPARQL
    0004  Neptune Analytics, not Neptune Database
    0005  Vectors in the graph store, not a separate index
    0006  Titan Text Embeddings V2 at 1024 dimensions
    0007  Content-addressed chunks with a DynamoDB registry
    0008  The ingest log lives outside the graph
    0009  Typed agent tools, no raw query access
    0010  S3 snapshots are the system of record
    0011  Hard delete on withdrawal, no tombstone
    0012  Snapshot diff is the delta source
    0013  One ecosystem, deliberately pinned repos
    0014  A single Terraform state

Status is one of Proposed, Accepted, Superseded by NNNN. A decision that turns out wrong gets
a new ADR explaining why, and the old one stays. The record of what you believed and when is
the point.
