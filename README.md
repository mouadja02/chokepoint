# chokepoint

A knowledge graph over Python dependencies and OSV advisories, with an agent that
answers why a repo is exposed and what changed since yesterday.

Bootstrap so far: the infrastructure is up, two OSV snapshots are in S3, and the model,
the delta semantics and the decisions behind them are written down. The graph, the
delta engine and the agent are not built yet.

## Why a graph and not a vector store

Three questions that need traversal:

- **Why am I exposed?** `web-api -> fastapi@0.104 -> starlette@0.27 -> anyio@3.7 -> [advisory]`.
  Nobody picked `anyio`. Provenance is multi-hop or it's nothing.
- **Which single upgrade removes the most exposure?** The version bump that dominates
  the largest number of vulnerable paths. That's the chokepoint, hence the name.
- **What changed since Friday?** An advisory gets withdrawn. Can the ticket be closed?

The third is the hard one. Advisories get withdrawn, CVSS scores get rescored,
affected ranges get narrowed. The graph has to handle facts that stop being true,
which means deleting nodes, edges and vectors, not only adding them. Most graph demos
never delete anything.

## The model

Six node types.

    (:Repo)-[:DECLARES {direct}]->(:Version)
    (:Package)-[:HAS_VERSION]->(:Version)
    (:Version)-[:DEPENDS_ON {scope, source}]->(:Version)
    (:Version)-[:AFFECTED_BY {introduced, fixed, source_range}]->(:Advisory)
    (:Advisory)-[:HAS_CHUNK]->(:Chunk {chunk_key})
    (:Package)-[:MAINTAINED_BY]->(:Maintainer)

Node ids are the natural keys -- PURLs for packages and versions, the OSV id for
advisories, the content hash for chunks -- which is the only uniqueness Neptune
enforces and the reason duplicates can't happen. `AFFECTED_BY` and `HAS_CHUNK` are
derived, so they carry provenance: withdrawing an advisory means finding everything it
produced.

`DECLARES` points at a version, not at a package. A lockfile pins a version, and
losing which one loses the start of every path. Full reference in `docs/schema.md`.

## Layout

    docs/       written before the code, on purpose
      glossary.md          start here if "ontology" and "LPG" are new
      ontology.md          the method, and how this model was derived with it
      schema.md            normative: labels, properties, edges, invariants
      knowledge-graph.md   ontology -> loaded graph. identity, idempotency, loading
      deltas.md            keeping it current, and deleting correctly
      agent-tools.md       the five tools, and why there is no sixth
      evaluation.md        the three harnesses
      runbook.md           create, load, tear down, and what it costs per hour
      adr/                 14 decisions, with the reasoning attached
    chokepoint/ pipeline code
      ingestion/           stage 1: the OSV export into S3, unmodified
    infra/      terraform: VPC, staging bucket, DynamoDB, SSM, the snapshot lambda
    scripts/    the same snapshot by hand, for catching up a missed day

`ontology.md` and `deltas.md` are the two that matter. The ADRs cover why Neptune
Analytics and not Neptune Database, why openCypher over Gremlin and SPARQL, and why a
withdrawn advisory is deleted rather than flagged.

## Infrastructure

One AWS account, `us-east-1`. State lives in `chokepoint-tfstate`, created by hand
because Terraform can't bootstrap its own backend.

    cd infra
    terraform init -backend-config=config/backend.conf
    terraform plan

One state file for the whole project. Everything under `infra/` is a single stack.

The state bucket is the one thing Terraform doesn't manage, so its lifecycle rule is
applied out of band and kept in `config/tfstate-lifecycle.json`:

    aws s3api put-bucket-lifecycle-configuration --bucket chokepoint-tfstate \
      --lifecycle-configuration file://config/tfstate-lifecycle.json

Noncurrent versions expire after a day and delete markers get swept. `use_lockfile`
writes and deletes a lock object on every operation, and with versioning on each cycle
otherwise leaves a version and a delete marker behind forever -- half an hour of work
had already left 20 of them. The tradeoff is that state history only goes back a day.

A few things worth knowing before you change anything:

- The provider sets `allowed_account_ids`. If `AWS_PROFILE` points somewhere else the
  plan fails instead of creating resources in the wrong account.
- `chokepoint-data-staging` is created and owned by Terraform like everything else. It
  used to be adopted through an import block instead, on the grounds that a snapshot for
  a day that has already passed can't be fetched back -- that guard didn't survive the
  28 August teardown, which took the bucket and its two snapshots with it. Nothing
  protects the snapshots now except not running `terraform destroy`.
- NAT gateway is off. Nothing runs in a private subnet yet and it's ~$32/month. The S3
  and DynamoDB gateway endpoints are free and already attached to the private route
  tables. Flip `enable_nat_gateway` when a Lambda needs egress.

## Cost

Neptune Analytics bills provisioned memory by the hour for as long as the graph
exists. Not per query, not only while it's busy. The floor is 32 m-NCU, and the
pricing page's own worked example implies about $0.03 per m-NCU-hour -- call it
$0.96/hour, or €700 for a month left running. Verify the rate before creating
anything; the order of magnitude is the point, and it dwarfs everything else here.

So the loop is create, load, work, **delete the graph**, every session. A €30-60
budget is 30-60 hours of graph uptime for the entire project. The rebuild takes
minutes, and being forced through it daily is what keeps the pipeline genuinely
reconstructible -- the cost discipline and the architectural property turn out to be
the same habit. See `docs/runbook.md`.

Embeddings survive teardown because they live in the chunk registry keyed by content
hash, so rebuilding costs nothing at Bedrock.

## Tables

Two, both on-demand:

`chunk-registry` keyed on `chunk_key`, the content hash of an advisory chunk. It maps
a hash to the embedding already paid for, so re-ingesting an unchanged advisory makes
zero Bedrock calls, and it holds the reference set that decides when a vector can
actually be deleted -- two advisories can share a chunk. Store the referencing
advisory ids as a set, not a counter: deltas get replayed, and an integer that
double-counts on retry never releases the vector. The `advisory_id-index` GSI exists
because withdrawing an advisory means finding every chunk it produced, and without it
that's a scan.

`ingest-log` keyed on `(snapshot, advisory_id)`, one row per advisory that changed in
a given snapshot. This is what `what_changed(since)` reads. It can't read the graph:
a withdrawn advisory is deleted from the graph, so the log is the only surviving
record that it was ever there. The `applied_at-index` GSI turns that into a time range
query instead of a walk over every snapshot.

## Snapshots

    scripts/init-snapshot.ps1     # Windows
    scripts/init-snapshot.sh      # everywhere else

Meant to run daily, and nothing schedules it yet -- no cron, no scheduled task, no
EventBridge rule. Until there is one it's a thing you have to remember, and the OSV
export is the one input that can't be backfilled: a day not snapshotted is a delta that
no longer exists anywhere.

The bucket name comes from `/chokepoint/dev/staging_bucket` in SSM; set `BUCKET` to
override. Objects land under `osv/raw/PyPI/<UTC hour>/`.

Two snapshots 23 hours apart, 26-27 August, give a sense of the churn:

    unique advisory ids    25073 -> 25077
    added                  4
    updated in place       14
    withdrawn              0

Note `modified_id.csv` is keyed on `(modified_timestamp, id)`, so diffing it line by
line reports 18 added and 14 removed for the same day. Diff on the id column.

Zero withdrawals in a day is the normal case. That's why the delta tests replay
historical withdrawals mined out of `all.zip` instead of waiting for one to happen --
`all.zip` contains every advisory that was ever retracted, and dropping the
`withdrawn` key reconstructs the record as it looked while still valid. Replaying that
pair through the real ingestion path is a test; waiting on upstream is not.

## Scope

One ecosystem (PyPI), five dependency sets, six node types, five agent tools. Widening
the corpus is time not spent on the deletion semantics, which are the point.
