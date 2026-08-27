# Schema

Normative. The database enforces none of it, so the loader enforces all of it. If code and
this file disagree, one of them is a bug — decide which, fix it, don't leave both.

Derivation and rejected alternatives: `ontology.md`.

## Node IDs

Every node's `~id` is its natural key. Neptune has no uniqueness constraint except `~id`, so
this is what makes duplicates structurally impossible instead of merely unlikely.

    Repo        repo:<name>                        repo:web-api
    Package     pkg:pypi/<normalized-name>         pkg:pypi/flask-sqlalchemy
    Version     pkg:pypi/<normalized-name>@<ver>   pkg:pypi/fastapi@0.104.1
    Advisory    <osv id>                           GHSA-qw6w-4wv3-5j4p, PYSEC-2023-135
    Chunk       chunk:<algo>:<hex>                 chunk:sha256:9f2b...
    Maintainer  maintainer:pypi/<handle>           maintainer:pypi/tiangolo

`<normalized-name>` is PEP 503: lowercase, runs of `-`, `_` and `.` collapsed to a single
`-`. Normalise at the boundary, once. `<ver>` is the version string exactly as PyPI
publishes it, not re-normalised — `1.0.0` and `1.0` are different releases.

Package and version ids are PURLs, so they join against deps.dev, OSV, SBOM tooling and
anything else in this ecosystem without a mapping table.

## Nodes

### Repo

    name          string   required   key. "web-api"
    lockfile      string   required   path of the lockfile it was read from
    last_scanned  string   required   ISO 8601 UTC

### Package

    name          string   required   PEP 503 normalized
    ecosystem     string   required   constant "PyPI" in this project. kept for the PURL
                                      and for anyone reading the graph cold.
    deprecated    bool     optional   absent means unknown, not false

### Version

    version       string   required   as published: "0.104.1", "2.0.0rc1", "1.0.post1"
    published_at  string   optional   PyPI upload time, if you fetch it
    sort_key      string   optional   see below

`sort_key` is a zero-padded, PEP 440-ordered encoding of `version`. Add it only if you need
to order versions *inside* a query — openCypher compares strings, and string order puts
`0.9` after `0.10` and `1.0rc1` after `1.0`. Range evaluation happens in Python, where
`packaging.version` is correct, so most of the time you don't need this. If `best_upgrade`
ends up ranking candidate versions in Cypher, you do.

### Advisory

    id            string   required   key. OSV id
    aliases       list     optional   ["CVE-2023-1234"]. list-valued property, not nodes
    summary       string   optional   one line, from OSV
    severity      string   optional   LOW | MODERATE | HIGH | CRITICAL
    cvss_score    float    optional   0.0 - 10.0
    cvss_vector   string   optional   "CVSS:3.1/AV:N/AC:L/..."
    published_at  string   required   ISO 8601 UTC
    modified_at   string   required   ISO 8601 UTC. the delta trigger. never trust it
                                      blindly -- see deltas.md
    snapshot      string   required   the snapshot stamp this state came from

No `withdrawn_at`. A withdrawn advisory is deleted, so the property could never be read
back. The withdrawal is recorded in the ingest log instead — see
[ADR-0011](adr/0011-hard-delete-on-withdrawal.md). If you change that decision, change this
line in the same commit.

`severity` is derived. OSV gives you `severity[]` (CVSS vectors) and sometimes
`database_specific.severity` (the word). Decide one derivation rule, write it in the loader,
and apply it to every advisory — mixed sources here produce a graph where `min_severity`
filtering is subtly wrong.

### Chunk

    chunk_key     string   required   key, = the node id. content hash, see below
    text          string   required   the chunk as embedded
    section       string   required   summary | details | remediation
    model_id      string   required   which embedding model produced the vector
    dim           int      required   its dimension

The vector itself is not a property. It lives in the graph's vector index, attached to this
node — see `knowledge-graph.md`.

`chunk_key` hashes the text *and* the embedding parameters:

    chunk_key = sha256(model_id | dim | normalizer_version | normalized_text)

Not just the text. If you swap models or dimensions, every key changes and every chunk
correctly re-embeds. If you hash text alone, a model change leaves the graph holding vectors
from two different spaces, which is silent, and the k-NN results are garbage in a way no
test catches.

### Maintainer

    handle        string   required   key

First thing on the cut list. If you drop it, drop `MAINTAINED_BY` and competency question
C10 with it.

## Edges

    (:Repo)-[:DECLARES]->(:Version)
        direct        bool     required   true = named in the lockfile's own requirements
        resolved_at   string   required   when this resolution was recorded

    (:Package)-[:HAS_VERSION]->(:Version)
        (no properties)

    (:Version)-[:DEPENDS_ON]->(:Version)
        scope         string   required   runtime | dev | optional
        resolved_at   string   required
        source        string   required   deps.dev | metadata | lockfile

    (:Version)-[:AFFECTED_BY]->(:Advisory)
        introduced    string   required   version string, or "0"
        fixed         string   optional   absent means no fix published
        last_affected string   optional   OSV's alternative to `fixed`. at most one of the two
        range_type    string   required   ECOSYSTEM | SEMVER
        source_range  string   required   which affected[].ranges entry produced this edge
        derived_at    string   required

    (:Advisory)-[:HAS_CHUNK]->(:Chunk)
        ordinal       int      required   position within the advisory's prose

    (:Package)-[:MAINTAINED_BY]->(:Maintainer)
    (:Package)-[:SUPERSEDED_BY]->(:Package)
        (no properties)

`DECLARES` points at `Version`, not at `Package` as the spec's sketch has it. A lockfile
pins a version; pointing at the package loses which one, and `explain_path` starts at the
resolved version. Reach the package with `HAS_VERSION` when you need the name.

`AFFECTED_BY` and `HAS_CHUNK` are derived, which is why they carry provenance. Everything
else is read straight from a lockfile or a resolver.

## Cardinality

    Repo      -> Version     many, one per locked dependency
    Version   -> Package     exactly one (via incoming HAS_VERSION)
    Version   -> Version     many (DEPENDS_ON), and it's a DAG in theory. cycles exist in
                             practice; every traversal needs a depth bound.
    Version   -> Advisory    many
    Advisory  -> Chunk       1..n, typically 1-4
    Package   -> Maintainer  many

## Invariants the loader enforces

Assert these. A failure here is a bug in ingestion, not bad input.

1. Every `Version` has exactly one incoming `HAS_VERSION`.
2. No `AFFECTED_BY` without `introduced`, `range_type` and `source_range`.
3. At most one of `fixed` / `last_affected` on an `AFFECTED_BY`.
4. Every `Chunk` has exactly the `chunk_key` that hashing its own `text` produces.
5. No `Chunk` without an incoming `HAS_CHUNK` (an orphan chunk means a failed deletion).
6. Every `Chunk` in the graph has a vector in the index, and every vector has a chunk.
7. No node id appears with two different labels.
8. `severity`, when present, is one of the four allowed values.

4, 5 and 6 are the ones that catch real bugs. Run them after every delta apply, not only
after a rebuild.

## Magnitudes

Rough, from the 27 August PyPI snapshot. Use them to spot a load that went wrong by an order
of magnitude.

    Advisory      ~25,000        the whole PyPI export
    Chunk         ~50,000        2 per advisory, roughly
    Package       ~200           5 repos, deduplicated
    Version       ~250           some packages appear at two versions
    DECLARES      ~250
    DEPENDS_ON    ~600
    AFFECTED_BY   ~50-200        the interesting number. if it's 0, your range logic is
                                 broken. if it's 10,000, you're matching everything.

Only the advisories are big, and only because loading the whole export is easier than
filtering it. If memory ever matters, load only advisories whose `affected[].package.name`
is one you actually hold.

## Changing this file

The graph is rebuildable from S3 in minutes, so a schema change is a rebuild, not a
migration. That's a deliberate property — see
[ADR-0010](adr/0010-s3-is-the-system-of-record.md). Change the schema, change the loader,
drop the graph, rebuild, re-run the invariants. Don't write migration code; you'd be
maintaining it for a graph that gets deleted every evening anyway.
