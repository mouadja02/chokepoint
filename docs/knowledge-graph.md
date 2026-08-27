# From ontology to a loaded graph

The ontology says what the graph means. This says how records become nodes, and what breaks
if you do it in the wrong order.

Read `ontology.md` and `schema.md` first.

## The pipeline

Seven stages. Keep them separable — the delta path re-uses every one of them, and a stage
you can't run alone is a stage you can't debug.

    1  acquire      pull the OSV export and the lockfiles into S3, unmodified
    2  normalize    source JSON -> canonical records. one shape per label
    3  resolve      assign identity. PEP 503, PURLs, node ids
    4  materialize  canonical records -> nodes and edges (including range evaluation)
    5  embed        chunk prose, hash, look up the registry, call Bedrock only on misses
    6  load         write to Neptune: bulk CSV for a rebuild, upserts for a delta
    7  verify       counts, invariants, spot checks

Stage 1 is done (`scripts/init-snapshot.*`). Stages 2-4 are pure functions with no AWS in
them, which is what makes them testable — keep it that way. If a unit test for range
evaluation needs credentials, the seam is in the wrong place.

## Identity, and the one trick worth knowing

Neptune gives you exactly one uniqueness guarantee: node `~id`. There are no unique
constraints, no schema, no indexes you can declare. So make the natural key the id:

    MERGE (a:Advisory {`~id`: 'GHSA-qw6w-4wv3-5j4p'})
      ON CREATE SET a.published_at = $published_at
      SET a.modified_at = $modified_at, a.severity = $severity

Two things follow, and they're the difference between a graph that stays clean and one that
grows quiet duplicates:

**MERGE on the key alone, SET everything else.** `MERGE` matches the *entire* pattern you
give it. `MERGE (a:Advisory {id: $id, severity: $sev})` matches nothing when the severity
changed since last run — so it creates a second advisory node with the same `id` and you now
have two, forever, with no error. This is the single most common way people corrupt a graph,
and with `~id` as the key it can't happen: Neptune rejects a second node with the same id.

**Ids must be reproducible.** No sequence numbers, no UUIDs, no insertion order. The
rebuild-from-scratch test compares two independently built graphs; anything non-deterministic
in id assignment fails it, and you'll spend a day thinking the loader is non-deterministic
when it's only the ids.

`~id` in openCypher is written with backticks: `` {`~id`: $value} ``. It also works in
`MATCH` and in bulk-load CSV, where the column header is `:ID`.

## Where the dependency edges come from

The trap: `pip freeze` and a lockfile give you the resolved *set* of packages. They don't
give you the edges. Nothing in a `requirements.lock` says `fastapi` is why `anyio` is there —
and `explain_path`, the whole point of the project, is exactly that chain.

Three ways to get edges, in the order I'd try them:

**deps.dev.** Google's API returns the resolved dependency graph for a package version:
nodes, edges, and which are direct. One HTTP call per version, no resolver to write, and it
agrees with what pip would have done closely enough for this. Use it, cache the responses in
S3 next to the snapshots so the graph stays rebuildable offline.

**Installed metadata.** `importlib.metadata.requires()` on the venv you built gives
`Requires-Dist` lines. Real, local, and exact for that install — but the lines carry
environment markers (`; python_version < "3.9"`) and extras (`httpx[http2]`) that you have to
evaluate yourself, and getting marker evaluation wrong invents edges that don't exist.

**pipdeptree.** Renders the tree for an installed venv. Fine as a cross-check for the
verification step. I wouldn't build ingestion on it.

Pick one, record it in the `source` property on `DEPENDS_ON`, and use another as the
hand-verification for week 1's gate. Two sources disagreeing is information; one source is
an assumption.

## Turning OSV ranges into AFFECTED_BY edges

The hardest correctness work in the project, and the least glamorous. Get it wrong and every
downstream answer is wrong in a way that looks plausible.

An OSV record contains `affected[]`, one entry per package. Each entry has some combination
of:

    package        { ecosystem, name, purl }
    ranges[]       [{ type: ECOSYSTEM|SEMVER|GIT, events: [...] }]
    versions[]     an explicit list of affected version strings
    database_specific

`events[]` is a sorted sequence of `{introduced: X}`, `{fixed: Y}` and `{last_affected: Z}`.
The semantics: a version is affected if it's at or after an `introduced` and strictly before
the next `fixed` (or at or before a `last_affected`). `introduced: "0"` means "from the
beginning". A single range can open and close several times.

Rules that will save you:

- **`versions[]` wins when it's present.** It's the enumerated ground truth. Use the ranges
  only to decide about versions not in that list.
- **`type: ECOSYSTEM` means compare with the ecosystem's own ordering** — PEP 440 for PyPI.
  Not semver, not string comparison. Use `packaging.version.Version`. `1.0.post1 > 1.0`,
  `1.0rc1 < 1.0`, `1.0.0 == 1.0`. String comparison gets all three wrong.
- **Skip `type: GIT` ranges.** They're commit ranges. You have no commits.
- **One edge per (version, advisory, range).** `source_range` on the edge says which range
  produced it, which is what makes narrowing a range a targeted edge deletion rather than a
  recompute of the whole advisory.
- **Only evaluate against versions you hold.** You have ~250 `Version` nodes, not all of
  PyPI. The loop is over your versions, not over the advisory's range space.
- **Unparseable versions exist.** Some PyPI releases aren't PEP 440-valid. Decide the policy
  once — I'd log and treat as not-affected — and count how often it fires. A silent `except:
  continue` here is how you end up under-reporting exposure.

Write the range evaluator as a pure function with a table of cases before you wire it to
anything. It's the one component in this project that deserves property-based tests.

## Chunking and embedding

**What to chunk.** Advisory prose only: `summary` and `details`. Not the ranges, not the
package names, not the ids — those are structure, and structure is what the graph is for.
Embedding structured fields is how you end up with a vector store that badly re-implements a
`MATCH`.

**How to chunk.** The `details` field is usually a few hundred words of markdown. One chunk
per advisory is defensible; splitting on headings when it's long is better. Don't build a
recursive splitter with overlap tuning — you have ~25,000 short documents, not a book.

**The key.** `chunk_key = sha256(model_id | dim | normalizer_version | normalized_text)`, as
in `schema.md`. Normalisation means collapsing whitespace and stripping trailing markdown —
whatever you do, version it, because changing normalisation silently changes every key.

**The registry.** Before embedding, look the key up in the DynamoDB `chunk-registry` table.
Hit means the vector already exists; skip Bedrock entirely. That's the "zero embedding calls
on an unchanged re-ingest" assertion from week 2, and it's the assertion worth writing
first, because it fails loudly when the key derivation is unstable.

**Refcounts should be a set, not a number.** The registry row needs to know how many
advisories reference a chunk so deletion is safe. Store the *set of advisory ids*, not an
integer:

    ADD referenced_by :advisory_id      -- idempotent, replay-safe
    ADD refcount 1                      -- double-counts on retry, and retries happen

Deltas get replayed. Step Functions retries. At-least-once delivery is the normal case, not
the failure case. An integer counter that drifts up never releases the vector; one that
drifts down deletes a vector another advisory is still using. A set converges to the right
answer no matter how many times you apply the same event.

**Embedding model.** `amazon.titan-embed-text-v2:0`, 1024 dimensions, normalize on. It also
supports 512 and 256, and the dimension is baked into the graph at creation time — see
[ADR-0006](adr/0006-titan-embeddings-v2.md) before you pick.

## Loading

### Create the graph before you have anything to load

The vector index dimension is set **when the graph is created** and can't be changed
afterwards. One index per graph, dimension 1–65,535.

And the failure mode when you forget: *if embeddings are present in a load file but no vector
index exists, Neptune loads the graph and silently ignores the embeddings.* No error. You
find out when k-NN returns nothing. Check the graph's vector configuration before your first
load, and make it a startup assertion in the loader.

### Two write paths

**Bulk CSV, for rebuilds.** Write node and edge CSVs to S3 and call `neptune.load()`. The
node CSV carries the embedding in an `embedding:vector` column, semicolon-separated floats:

    :ID, text:String, embedding:Vector, :LABEL
    chunk:sha256:9f2b,"heap overflow in ...",0.013;-0.442;0.98;...,Chunk

Fastest path from zero to a loaded graph, which matters because you'll do it daily. Wrong
dimension in that column fails the whole load with a `ParsingException` naming the line.

**Upserts, for deltas.** `MERGE` for nodes and edges, `neptune.algo.vectors.upsert` for
vectors. One record at a time, or small batches.

### Vector writes are not transactional, and this changes how you write them

From the Neptune docs, and it's the constraint that most shapes the delta code: **updates to
the vector index are not atomic and not isolated.** A vector write becomes durable and
visible to other queries immediately, *even if the query that made it later fails*. Graph
mutations in the same query still roll back. Vector changes don't.

Three consequences:

1. **Never chain a vector write with graph mutations.** Run the `MERGE` that creates the
   chunk node, then a separate query that upserts its vector. If the combined query fails
   halfway you get a vector with no node, which violates schema invariant 6 and is invisible
   until the orphan sweep.
2. **`MATCH` then upsert, never `CREATE` then upsert.** AWS is explicit about this: the
   `MATCH`-based form is retry-safe, because on retry the node already exists and the upsert
   simply overwrites. The `CREATE` form fails on retry — the node exists — while the
   embedding from the first attempt is already committed. Idempotent by construction again.
3. **Don't update the same node's embedding concurrently.** Partition your delta work by
   advisory so two workers never touch one chunk.

### Order of operations

For a load:

    graph created with vector index -> nodes -> edges -> vectors

For a delete (this order is forced, and it's easy to get backwards):

    remove the vector  ->  delete the chunk node  ->  delete the edges  ->  delete the node

`neptune.algo.vectors.remove` takes a node. Delete the node first and you've lost the handle
to its vector, which is then an orphan in the index with nothing pointing at it. There's no
"list all vectors" call to find it with afterwards.

## Verification

The week 1 gate is "rebuild from S3 from zero, twice, and get an identical graph". Make that
mechanical:

**Counts.** Nodes per label, edges per type. Compare against the magnitudes in `schema.md`,
then against the previous build.

**Checksum.** Sort node ids, hash the sorted list; same for edges as
`(from, type, to, sorted properties)` tuples. Two builds of the same snapshot must produce
the same two hashes. Sort explicitly — query result order isn't guaranteed and an unsorted
checksum will flap and waste an afternoon.

**Invariants.** The eight assertions in `schema.md`, as queries. Run after every load and
every delta.

**Hand checks.** Pick one repo. Verify by eye against `pip show` that the `DEPENDS_ON` chain
is real. Pick one CVE you know applies and confirm the `AFFECTED_BY` edge exists with the
right `introduced` and `fixed`. Two hand checks catch more than fifty generated ones, at this
stage.

**Vector count.** Number of `Chunk` nodes must equal the number of vectors. If the index has
no count call, verify by sampling: k-NN on a known chunk's own text should return that chunk
first, with distance near zero.

## Bootstrap order

The order that unblocks the most work per hour:

1. Lockfiles to `Repo`/`Package`/`Version`/`DECLARES` nodes. No advisories. Verify counts by
   hand against a lockfile.
2. `DEPENDS_ON` from deps.dev. Verify one chain by hand. Now `explain_path` is answerable in
   raw Cypher, without an agent.
3. OSV advisories as nodes, no edges. Cheap and boring.
4. Range evaluation, `AFFECTED_BY`. This is the day that takes two days.
5. Rebuild from zero, compare checksums.
6. Only then: chunks, embeddings, vectors.

Steps 1-5 need no Bedrock, no vector index and no agent. If you're behind schedule, that
sequence still produces a defensible project on its own.
