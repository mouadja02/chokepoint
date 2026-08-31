# Building the ontology

A method, then this project's ontology derived with it. If you've never done this before,
read it in order — the derivation at the end only makes sense once you've seen the
questions it answers.

## What you're actually building

An ontology is a contract about meaning. It says which kinds of thing exist, which
connections between them are legal, and what identifies each one. That's it. Everything
else people attach to the word — OWL, reasoners, upper ontologies, the Semantic Web — is
one particular tradition's way of writing it down, and you're not in that tradition. See
[ADR-0002](adr/0002-property-graph-over-rdf.md).

In a property graph the ontology is:

    labels             the kinds of node           Advisory, Package, Version
    relationship types the kinds of edge           AFFECTED_BY, DEPENDS_ON
    endpoints          what connects to what       (:Version)-[:AFFECTED_BY]->(:Advisory)
    properties         with types, per label       Advisory.cvss is a float
    keys               what identifies an instance Advisory.id
    cardinality        how many are allowed        a Version has exactly one Package
    invariants         rules the data must satisfy no AFFECTED_BY without introduced

Nothing in the database enforces any of this. Neptune has no schema, no constraints, no
uniqueness except node ID. Every rule above is a rule your loader keeps, or doesn't. That's
the single most important thing to understand before you start: **the ontology lives in
your code and in `schema.md`, and the graph will happily contradict both.**

Which means writing it down isn't paperwork. It's the only copy.

## Where to start: competency questions

Not with the data. Not with a diagram. With the questions the graph has to answer, written
as sentences, before any modeling.

This is the standard method and it works because it's falsifiable: for every question you
can check whether a traversal exists that answers it. If you can't draw the traversal on
paper, the model is wrong, and you find that out in an afternoon instead of in week three.

CHOKEPOINT's list:

    C1  Which advisories currently affect repo X?
    C2  Which of those are at least HIGH severity?
    C3  Why is repo X exposed to advisory A? Show the package chain.
    C4  Which repos are exposed through package P, directly or transitively?
    C5  How many CRITICAL advisories affect any repo?
    C6  Which single version upgrade removes the most exposures across all repos?
    C7  What changed between snapshot S1 and S2, and does it change the answer to C1?
    C8  Was repo X ever affected by advisory A, given the range was narrowed on Tuesday?
    C9  Is this advisory exploitable without authentication?     (prose, not structure)
    C10 Which packages have no maintainer listed?

Now sort them, because the sort tells you what the model is for:

- **C1, C2, C5** are lookups and aggregations. A relational table would do. They aren't why
  you're here, but they must not regress.
- **C3, C4, C6** are traversals over unbounded-length paths. This is the graph's reason to
  exist. C6 is an optimisation over the whole graph.
- **C7, C8** are temporal. They decide how deletion works, which is the hardest decision in
  the model. See "Time" below.
- **C9** is prose. No structure will answer it; it's the vector leg.
- **C10** is a modeling smell. Ask whether anything downstream depends on it. If not, cut
  the concept. (It's on the spec's cut list, and that's the right call.)

Write your list before you look at an OSV record. Then look, and notice which questions the
data can't support — that's cheaper to learn now than after you've built a loader.

## The five questions you ask about every concept

For each noun in your competency questions, in order:

### 1. Node or property?

Default to property. Promote to node only when one of these is true:

- something else needs to point at it
- it has attributes of its own
- you need to traverse *out* of it to somewhere else
- it has an identity that's referenced from outside your system

Keep it a property when it's low cardinality, you only ever filter on it, and it has no
attributes of its own.

The arithmetic matters. Your snapshot holds ~25,000 PyPI advisories and `severity` has four
values. Model it as a node and you get four nodes with ~6,000 edges each. Every query that
mentions severity now fans out across a supernode, and you gained nothing, because nobody
ever asks "what else is connected to HIGH". Same reasoning kills `ecosystem`, which has
exactly one value in this project.

The counter-example in the same model: `Package` looks like it could be a property of
`Version` (`version.package_name`). It's a node because C4 traverses from a package to every
repo exposed through it, and because `deprecated` and `SUPERSEDED_BY` hang off it.

### 2. Edge or node?

An edge that needs its own identity — something else points at it, or it participates in
another relationship — has to become a node. That's reification, and in an LPG you almost
never need it, because edges carry properties natively. This is the main practical advantage
of LPG over RDF and you should be able to say so.

`AFFECTED_BY` is the test case. It has attributes: `introduced`, `fixed`, the source range it
came from. In RDF that forces a node (or RDF-star). Here it stays an edge with properties,
and the model stays six labels wide.

Promote an edge to a node when you find yourself wanting to point at the relationship
itself. You won't, here.

### 3. Which direction?

For correctness, direction doesn't matter — you can traverse either way. It matters for
readability and for how you'll write every query for the next month.

Rule: **subject verbs object**, active voice, and read the pattern aloud.

    (:Repo)-[:DECLARES]->(:Version)              "repo declares version"
    (:Version)-[:DEPENDS_ON]->(:Version)         "version depends on version"
    (:Version)-[:AFFECTED_BY]->(:Advisory)       "version is affected by advisory"

`AFFECTED_BY` reads as passive but points from the thing you own toward the thing you don't,
which keeps every exposure query flowing one way: repo, package, version, advisory.
Consistency of flow is worth more than grammatical purity.

Pick once, write it in `schema.md`, never flip it. Flipping a direction after the loader
exists is a rewrite of every query and every test.

### 4. What is its identity?

The question people skip and then pay for. For each label: what makes two instances the
same instance?

- **Prefer identifiers the outside world already assigns.** `GHSA-xxxx-xxxx-xxxx` for
  advisories. `pkg:pypi/fastapi@0.104.1` — a PURL — for versions. Stable, globally unique,
  and they mean you can join against anything else in the ecosystem later.
- **Never key on a mutable property.** An advisory's `summary` changes; its id doesn't.
- **Never key on your own sequence numbers.** They aren't reproducible, and this graph gets
  rebuilt from scratch on purpose. A rebuild that produces different ids fails the
  determinism test in week one.
- **Case and normalisation are part of the key.** PyPI names are case-insensitive and treat
  `_`, `-` and `.` as equivalent: `Flask-SQLAlchemy`, `flask_sqlalchemy` and
  `flask.sqlalchemy` are one package. Normalise once, at the boundary, per PEP 503, and
  record that you did.

Then make the key literally *be* the node id. Neptune lets you set `~id` on create, and
`~id` is the only uniqueness the engine gives you. If the natural key is the id, duplicates
are impossible by construction rather than by discipline. This is the highest-value trick in
the whole document — see `knowledge-graph.md`.

### 5. Does it expire?

For each node, edge and property, ask: can this stop being true, and what happens when it
does?

    Advisory node        yes -- withdrawn. rare, and the point of the project.
    AFFECTED_BY edge     yes -- range narrowed. you were never affected after all.
    Advisory.cvss        yes -- rescored. property update, no structural change.
    Chunk text           yes -- description edited. re-embed exactly that chunk.
    DEPENDS_ON edge      yes -- you upgraded. subgraph rewrite.
    Package.name         no.
    Version.version      no.

Anything answering "yes" needs a decided deletion semantic before you write the loader, not
after. That's the next section.

## Naming

Boring and consistent beats clever.

    labels           PascalCase, singular       Advisory, Package, Version, Chunk
    relationships    SCREAMING_SNAKE, verb      DEPENDS_ON, AFFECTED_BY, HAS_CHUNK
    properties       snake_case                 chunk_key, published_at, withdrawn_at

Two more, learned the hard way by everyone:

- Timestamps end in `_at` and are ISO 8601 UTC strings. Not epoch ints, not local time.
  You'll be diffing them by eye at 2am.
- Don't name a property after its label (`Advisory.advisory`). Don't name an edge after its
  target (`HAS_ADVISORY` when the target is obviously an Advisory) — name it after the
  meaning: `AFFECTED_BY`.

## Reuse identifiers, not ontologies

There are existing vocabularies here: SPDX, CycloneDX, the OSV schema itself, STIX/UCO for
security. The temptation for a first ontology is to adopt one. Don't. They're built for
interchange between organisations, they carry a lot of structure you have no use for, and
mapping into them will eat a week.

What you should reuse, without exception, is **identifiers**: PURL for packages and
versions, GHSA/CVE for advisories, PEP 503 normalised names. Identity is the part that has
to interoperate. The shape of your graph is yours.

If someone asks why you didn't use SPDX, that's the answer: identifiers are shared, models
are local.

## Time, and facts that stop being true

This is the section that matters. Everything else here is craft; this is the project.

Four ways a graph can handle a fact ceasing to be true:

**1. Hard delete.** Remove the node or edge. Queries stay simple, current state is exactly
what's in the graph. You lose history entirely.

**2. Soft delete / valid time.** Keep it, add `valid_from` / `valid_to` or `withdrawn_at`,
and filter on every read. Keeps history. Costs a filter clause in *every single query*
forever, and one forgotten clause is a silently wrong answer — in this project, telling
someone they're vulnerable when they aren't.

**3. Versioned nodes.** A new node per state, chained. Fully correct, doubles the size of
the model and the complexity of every traversal.

**4. Event log outside the graph.** The graph holds current truth only; a separate,
append-only log records every transition. Queries stay simple and history is preserved, but
"what did the graph look like last Tuesday" now needs a replay rather than a query.

CHOKEPOINT uses **1 and 4**. The graph is current truth and nothing else; the DynamoDB
`ingest-log` table is the event log, one row per `(snapshot, advisory_id)` that changed.

Why not 2, which is what most people reach for: the load-bearing behaviour of this project
is that the agent *stops reporting* an exposure that no longer exists. With soft deletes
that's a filter you can forget, in any of five tools. With hard deletes it's a node that
isn't there, and it can't be returned by any query, including ones you write badly. Make the
invariant structural, not procedural.

The cost is real and you should say it out loud rather than hide it: C8 ("was I ever
affected") isn't answerable from the graph. It's answerable from the ingest log plus the S3
snapshots, which is where that question belongs — see
[ADR-0008](adr/0008-ingest-log-outside-the-graph.md) and
[ADR-0011](adr/0011-hard-delete-on-withdrawal.md).

One consequence to notice early: if withdrawal deletes the node, `Advisory.withdrawn_at`
never survives to be read. Either drop the property (it's write-only, so it's noise) or
decide instead to keep a tombstone node with its edges removed. Pick one and put it in
`schema.md`. The thing you must not do is leave the loader and the tests disagreeing about
whether the node exists.

## Provenance

Every derived edge records where it came from.

`AFFECTED_BY` isn't in the source data — you compute it by evaluating a version range from
an advisory against the versions you hold. So the edge carries `source_range` (which
`affected[].ranges` entry produced it) and the advisory id. Same for `HAS_CHUNK`: the chunk
records which advisory's text produced it.

This isn't documentation. It's what makes deletion possible. When advisory A is withdrawn you
have to find everything A produced — edges, chunks, vectors — and remove exactly that,
without touching anything another advisory also produced. If the derived edge doesn't say who
made it, your only options are a full rebuild or a scan, and the withdrawal path is where the
project gets judged.

Rule: **if you computed it, record the input that produced it.**

## Deriving the CHOKEPOINT model

Walking the method over the competency questions:

C3 ("why is repo X exposed") needs `Repo` and a chain to an `Advisory`. The chain runs
through packages, and the thing a vulnerability actually applies to is a *version*, not a
package — `fastapi` isn't vulnerable, `fastapi@0.104.1` is. So `Package` and `Version` split.
`Version` is a node rather than a property because `DEPENDS_ON` connects versions to
versions: that's the transitive edge, and it's the whole traversal.

C4 traverses outward from a package, which confirms `Package` as a node.

C1/C2 need severity filtering. Severity is four values, filtered and never traversed:
property on `Advisory`.

C6 compares candidate upgrades — for each `Version` of a `Package`, how many vulnerable paths
would disappear. Traversal plus counting over the existing model. No new labels.

C7/C8 are the temporal questions, answered by the ingest log rather than by structure. No new
labels, but they set the deletion semantics for `Advisory` and `AFFECTED_BY`.

C9 is prose, and prose has to be chunked to be embedded. Chunks are separate nodes rather
than a property on `Advisory` because an advisory yields several of them, each with its own
hash and its own vector, and because deletion is per-chunk. `Chunk` carries `chunk_key`, the
content hash — that one property is what makes incremental re-embedding possible, and it
belongs in the ontology, not in the loader.

C10 gives `Maintainer`. Keep it if you want a sixth label; it's the first thing to cut.

Result, six labels:

    (:Repo)-[:DECLARES {direct}]->(:Version)
    (:Package)-[:HAS_VERSION]->(:Version)
    (:Version)-[:DEPENDS_ON {scope, resolved_at}]->(:Version)
    (:Version)-[:AFFECTED_BY {introduced, fixed, source_range}]->(:Advisory)
    (:Advisory)-[:HAS_CHUNK]->(:Chunk {chunk_key, text})
    (:Package)-[:MAINTAINED_BY]->(:Maintainer)
    (:Package)-[:SUPERSEDED_BY]->(:Package)

Exact properties and types: `schema.md`.

Note what happened to `DECLARES`. A repo declares a *package*, but the lockfile pins a
*version*, and C3's path has to start somewhere. Two options: point `DECLARES` at the resolved
`Version`, or keep the package edge and reach versions through `HAS_VERSION`. The second one
is wrong — it can't tell you *which* version this repo resolved. Point it at the version, and
keep `direct` on the edge to distinguish "I asked for this" from "this came along". Work this
out before you load anything; it's the one place the spec's model is ambiguous.

## What got rejected, and why

Keep this list. It's the interview answer.

    (:Severity)         four values, 25k advisories, guaranteed supernode, never traversed
                        from. property.
    (:Ecosystem)        one value in this project. property, and arguably a constant.
    (:Range) node       reification with no payoff. the range's attributes fit on the
                        AFFECTED_BY edge, and nothing points at a range.
    (:CVE) / (:GHSA)    aliases of one advisory, not separate things. list-valued property.
    (:Fix) / (:Patch)   there's no reliable fix entity in OSV. the fixed version is an edge
                        property.
    (:Repo)-[:EXPOSED_TO]->(:Advisory)
                        a materialised shortcut for C1. tempting, and wrong for now: it's
                        derived from the path, so every delta has to maintain it, and C3
                        needs the real path anyway. Add it later only if C1 is measurably
                        too slow, and then only with provenance.

## The RDF words you'll meet

Most ontology material is written in RDF terms. Rough translation:

    rdfs:Class              -> node label
    rdf:Property            -> relationship type, or property key
    rdfs:domain / range     -> the endpoints of a relationship type
    owl:ObjectProperty      -> edge (points at a node)
    owl:DatatypeProperty    -> property (holds a literal)
    owl:inverseOf           -> traverse the edge backwards
    owl:TransitiveProperty  -> variable-length pattern, -[:DEPENDS_ON*]->
    SHACL shape             -> the assertion in your loader
    reasoner / inference    -> no equivalent. materialise it, or query for it.

The one genuine loss in LPG is inference: RDF can derive facts from rules, LPG can't. You
don't need it — `DEPENDS_ON*` at query time *is* the transitive closure, computed on demand,
and on demand is the right choice for data that changes daily.

## Is it done?

Every line must pass before you write a loader.

- [ ] Every competency question maps to a traversal you can write on paper.
- [ ] Every label has exactly one key, and that key is an external identifier.
- [ ] No label whose instances number in the single digits (that's a property).
- [ ] Every edge type has stated endpoints and a stated cardinality.
- [ ] Every property has a type and is marked required or optional.
- [ ] Every derived edge records its source.
- [ ] Every "yes" in the expiry table has a decided deletion semantic.
- [ ] Nothing in the model exists only because the source JSON has a field for it.
- [ ] You can name three things you deliberately left out.

## Mistakes to expect

From people doing this the first time, in rough order of frequency:

1. **Modeling the source format instead of the domain.** OSV records have `affected[]`,
   `ranges[]`, `events[]`. None of those are concepts in your graph; they're the encoding of
   one concept, "this range of versions is affected". Read the source, close it, then model.
2. **Everything is a node.** It feels safer. It produces supernodes and six-hop paths for
   one-hop questions.
3. **Keying on a name.** Then a name changes case, or normalisation, and you have two of
   everything.
4. **Deferring deletion.** Add-only is easy and every tutorial stops there. Deciding deletion
   semantics after the loader exists means rewriting the loader.
5. **No provenance on derived edges.** Discovered during the first withdrawal, which is also
   the demo.
6. **Growing the model when a query is hard.** A hard query usually means the wrong
   traversal, not a missing label.
7. **Letting `schema.md` drift.** The graph won't tell you. Nothing will tell you.

## Reading

- OSV schema: <https://ossf.github.io/osv-schema/> — read once, before modeling.
- PURL spec: <https://github.com/package-url/purl-spec> — your identity format.
- PEP 503 normalised names: <https://peps.python.org/pep-0503/#normalized-names>.
- Neo4j's data modeling guide is the least dogmatic LPG material available and applies to
  Neptune's openCypher nearly unchanged.
- Competency questions come from the Ontology Development 101 tradition (Noy & McGuinness,
  2001). The methodology is dated and RDF-flavoured; the questions idea is the durable part.
