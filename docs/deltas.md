# Deltas

Keeping the graph current. This is the part the project is judged on — adding nodes is a
tutorial, removing them correctly is not.

## The shape of the problem

Between two snapshots, some advisories changed. For each one you have to work out *what kind*
of change it was, because the graph operation differs completely:

    source event                    graph op                        vector op
    ---------------------------------------------------------------------------------
    new advisory                    add node + AFFECTED_BY edges     embed new chunks
    CVSS rescored                   SET property                     none
    range narrowed                  DELETE some AFFECTED_BY edges    none
    range widened                   MERGE new AFFECTED_BY edges      none
    description edited              MERGE new chunk, delete old      embed one chunk
    advisory withdrawn              DELETE edges, chunks, node       remove vectors
    package upgraded (yours)        rewrite DEPENDS_ON subgraph      none

The rightmost column is what makes this more than a database exercise: the vector index has
its own lifecycle, its own consistency rules, and no foreign keys.

Note the last row. Advisory churn arrives from the world on its own schedule; dependency
churn you trigger by editing a lockfile. Between the two, every delta type is reachable on
demand, which means none of your tests has to wait for upstream.

## Detecting

### Diff two snapshots

Snapshots land in `s3://<staging>/osv/raw/PyPI/<UTC hour>/`. The delta between any two is:

    load ids from snapshot A          -> set A
    load ids from snapshot B          -> set B
    added     = B - A
    removed   = A - B                  (rare -- OSV withdraws rather than deletes)
    changed   = { id in A n B : modified_at differs }

Key on the **advisory id**, always. `modified_id.csv` is keyed on
`(modified_timestamp, id)`, so a line-by-line diff of two of them reports every advisory
whose timestamp moved as one removal plus one addition — 18 added / 14 removed for the same
day that actually had 4 additions and 14 modifications. Parse the id column, diff on that.
This is written up in the README because it already cost time once.

### Don't trust `modified_at` alone

`modified_at` moving tells you the record was touched, not that anything you care about
changed. Republished records, upstream metadata edits and format migrations all bump it.
Use it as a cheap filter, then diff the fields that matter. Otherwise every OSV format change
day looks like 25,000 deltas and re-embeds your entire corpus.

The inverse also happens and is worse: a field changes without `modified_at` moving. Rare,
but it's why the full snapshot is kept rather than only the change feed — you can always
recompute the truth by diffing records, and a monthly full diff is a good sanity check
against drift.

## Classifying

For each changed advisory, compare old and new record field-by-field. Classification is a
**set, not an enum** — one record can be rescored *and* have its range narrowed *and* have
its prose edited in a single upstream edit. Code that picks one class with an if/elif chain
will apply the first and drop the rest, and the bug shows up as a stale edge weeks later.

    withdrawn          `withdrawn` key present in new, absent in old
    severity_changed   severity[] or database_specific.severity differs
    ranges_changed     affected[] differs (compare normalized, order-insensitive)
    prose_changed      summary or details differs after normalisation
    aliases_changed    aliases[] differs
    republished        modified_at moved, nothing above fired -- no-op, log it

`republished` earning a line matters: it's the class that proves your diff is precise. If
you never see one, you're over-classifying and re-embedding things that didn't change.

Compare `affected[]` after normalising — sort the ranges, sort the events, drop
`database_specific` — or key ordering alone will report changes that aren't.

## Applying

Every apply must be idempotent. Step Functions retries, S3 events are at-least-once, and you
will replay deltas by hand while debugging. "Applied twice equals applied once" isn't a nice
property here; it's a requirement.

### Added

    MERGE the Advisory node by ~id, SET all properties
    evaluate ranges against every Version you hold
    MERGE one AFFECTED_BY per (version, range) with provenance
    chunk the prose, hash, check the registry, embed only on a miss
    MERGE Chunk nodes, MERGE HAS_CHUNK, then (separate query) upsert vectors
    write the ingest-log row

### severity_changed

    MATCH the Advisory, SET cvss_score / cvss_vector / severity
    write the ingest-log row

No edge changes. No re-embedding — severity isn't in the chunked text, and if it is, take it
out. This is the delta whose test asserts **zero** Bedrock calls.

### ranges_changed

Recompute the affected version set for that advisory, then reconcile rather than replace:

    want = evaluate(new record) over your versions
    have = MATCH (v)-[e:AFFECTED_BY]->(a) RETURN e
    DELETE  have - want
    MERGE   want - have

Don't delete-all-then-recreate. It's simpler to write and it churns edges that didn't change,
which makes the ingest log lie about what happened and makes "range narrowed removed exactly
one edge" untestable.

Narrowing is the interesting direction: an edge disappearing means *you were never actually
affected*, and the answer to "can I close that ticket" is yes. That's a demo moment, so make
the log row say which edges went.

### prose_changed

    new chunks = chunk(new prose), hashed
    old chunks = MATCH (a)-[:HAS_CHUNK]->(c) RETURN c.chunk_key

    for key in new - old:   registry lookup; embed on miss; MERGE Chunk; MERGE HAS_CHUNK
    for key in old - new:   DELETE HAS_CHUNK; release the chunk (below)
    for key in both:        nothing. no re-embed, no vector write.

The "exactly one chunk re-embedded" assertion lives here. If an advisory has four chunks and
one sentence changed in the third, this does one Bedrock call. If it does four, the
normalisation isn't stable — usually whitespace or markdown that differs without meaning.

### withdrawn

The one that matters. Order is forced by the API surface:

    1  for each chunk of the advisory: release it (below)
    2  DETACH DELETE the Chunk nodes whose refcount hit zero
    3  DELETE the AFFECTED_BY edges
    4  DELETE the Advisory node
    5  write the ingest-log row with kind=withdrawn

Vector removal happens inside step 1, *before* the chunk node is deleted:
`neptune.algo.vectors.remove` takes a node. Delete the node first and the vector stays in the
index with nothing pointing at it and no way to enumerate it back.

Do the vector removal in its own query, not chained to the node deletion. Vector writes
aren't atomic with graph writes — see `knowledge-graph.md`.

The ingest-log row is not optional bookkeeping. Once step 4 runs, the graph has no record
this advisory ever existed, so the log is the only thing that can answer "what changed since
Friday" and the only evidence for the ticket you're closing.

### Releasing a chunk

    remove advisory_id from the registry row's referenced_by set   (DELETE from a string set)
    if the set is now empty:
        neptune.algo.vectors.remove(chunk node)
        DETACH DELETE the chunk node
        delete the registry row
    else:
        DELETE the HAS_CHUNK edge only. the chunk stays, another advisory needs it.

Two advisories sharing a chunk is not hypothetical — boilerplate remediation text repeats
across advisories, which is exactly why the registry exists.

Use set add/delete, never integer increment/decrement. A replayed delete on a set is a no-op;
a replayed decrement drops the count below zero and deletes a vector someone's still using.

### Package upgraded (yours)

You edit a lockfile. Re-resolve that repo, then reconcile `DECLARES` and `DEPENDS_ON` the
same way as ranges: compute the wanted edge set, delete what's extra, merge what's missing.
Versions that no longer appear anywhere become orphan `Version` nodes — either sweep them or
leave them; they're harmless and they let you answer "what did I upgrade from". Decide, and
write it down.

## The ingest log

One row per `(snapshot, advisory_id)` that actually changed:

    snapshot      2026-08-27T14         partition key
    advisory_id   GHSA-...              sort key
    kinds         [ranges_changed]      the classification set
    applied_at    ISO 8601              GSI sort key, with ecosystem as the GSI partition
    detail        { edges_removed: 1, chunks_reembedded: 0, ... }

`what_changed(since)` reads the GSI by time range. `detail` is what makes the answer useful
rather than a list of ids — "GHSA-x narrowed its range, one exposure removed" is an answer;
"GHSA-x changed" is a shrug.

Write the row **after** the graph and vector work succeeds. A log row for a delta that didn't
apply is worse than no row: it's a wrong answer with provenance attached.

## Replay fixtures

Withdrawals happen a few times a year. Your three weeks will very likely see zero — the
27 August snapshot pair had 4 additions, 14 modifications, 0 withdrawals, which is the normal
case.

So mine them instead. `all.zip` contains every advisory that was ever withdrawn, with the
`withdrawn` timestamp still on the record. Dropping that key reconstructs the record as it
looked while it was still considered valid:

    T0 = record without `withdrawn`   -> load it. advisory present, repos exposed, vectors in
    T1 = record as published          -> feed through the real classifier and applier

That's real data, replayed deterministically, through the production code path. Not a mock,
not a fixture someone hand-wrote to match the code's assumptions.

The same construction gives you the other rare events: take a real record, narrow one range,
bump one CVSS score, edit one sentence of `details`. Each becomes a T0/T1 pair. Build these
as data files, not as code that patches records at test time — a fixture you can `cat` is a
fixture you can reason about when the test fails at 1am.

One more thing to know: OSV files ecosystem-less records — typically withdrawn ones — under
`[EMPTY]/` in the export. If your ingestion filters by directory you'll skip exactly the
records you most need.

## Failure handling

    failure                       what to do
    ---------------------------------------------------------------------------------
    Bedrock throttles             retry with backoff. the registry means a retry after a
                                  partial batch re-embeds only what's still missing.
    Neptune query fails mid-apply graph mutations rolled back, vector writes did not.
                                  re-run the whole apply; every step is idempotent.
    the applier crashes           no ingest-log row was written, so the delta is still
                                  pending. re-run from the same snapshot pair.
    the graph was deleted         rebuild from S3, then replay deltas from the last logged
                                  snapshot. this is the normal daily path, not an incident.
    a vector is orphaned          the sweep finds it. see below.

**The orphan sweep.** A periodic check for the states that non-atomic vector writes can
leave behind: chunks with no incoming `HAS_CHUNK`, registry rows with an empty
`referenced_by`, chunk nodes with no vector. It's cheap at this scale and it's the only thing
standing between you and a slow leak in the index. Run it after the delta suite, and make it
report rather than silently repair — an orphan is a bug somewhere upstream, and auto-healing
hides it.

## What the tests assert

Full harness in `evaluation.md`. The shape, for every delta type:

    load T0  ->  assert the pre-state, including via the agent
    apply T1 through the real pipeline
    assert the post-state at all three layers:
        graph      node/edge present or gone
        vectors    index contains or doesn't
        agent      the tool's answer changed
    assert what_changed() reports it
    apply T1 again  ->  assert nothing changed  (idempotency)

That last line gets skipped by everyone and it's the cheapest test in the suite.
