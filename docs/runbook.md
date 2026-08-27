# Runbook

Operating the thing. Read the cost section before you create a graph, not after.

## Cost

Neptune Analytics bills for provisioned memory by the hour, for as long as the graph exists.
Not per query. Not while idle. While it exists.

    1 m-NCU            1 GiB of memory plus matching compute
    smallest graph     32 m-NCU  (was 128 until AWS added smaller units in 2024)
    us-east-1 rate     the pricing page's worked example implies ~$0.03 per m-NCU-hour

At the floor that's roughly **$0.96/hour, $23/day, $700/month if you leave it up**. Verify
the current rate before you create anything — but the order of magnitude is the point, and it
dwarfs everything else in this project. S3, DynamoDB on-demand, Bedrock embeddings and the
Lambdas together are a rounding error next to it.

A €30–60 budget for the month buys about **30–60 hours of graph uptime**. Two hours a day.
That's workable, and only if teardown is a habit rather than an intention.

So the loop is:

    create graph  ->  load from S3  ->  work  ->  DELETE THE GRAPH

Every session. The rebuild takes minutes, and forcing yourself through it daily is what makes
the pipeline genuinely reconstructible — the cost constraint and the architectural property
are the same discipline. That's worth saying out loud when someone asks why you delete it.

Set a billing alarm before the first graph, at whatever number would actually upset you.
A graph left running over a weekend is €50.

## Creating the graph

The two settings you can't change afterwards:

**Vector index dimension.** Set at creation, one index per graph, 1–65,535. It must match
your embedding model exactly — 1024 for Titan V2 at its default. Getting this wrong means
deleting the graph and rebuilding, which is cheap here, but only if you notice.

**And the failure mode if you skip it entirely:** loading data with embeddings into a graph
with no vector index succeeds, silently, ignoring the embeddings. No error, no warning. You
find out when k-NN returns nothing. Assert the graph's vector configuration at loader
startup.

**Capacity.** Start at 32 m-NCU. This graph is ~25k advisories and a few hundred packages —
it fits in a fraction of that. You're paying the floor regardless.

**Connectivity.** The data-plane API is IAM-authenticated (SigV4), so a public endpoint isn't
an open endpoint. Given the VPC has no NAT gateway and nothing runs in a private subnet yet,
public + IAM is the pragmatic choice for now. Revisit when a Lambda in a private subnet needs
to reach it — the VPC already has the S3 and DynamoDB gateway endpoints, but Neptune
Analytics needs an interface endpoint or NAT.

Record the graph id in SSM under `/chokepoint/dev/` the way the other resources are, so
nothing hardcodes it.

## A session

    1  create the graph (or restore a snapshot)
    2  assert vector dimension == the model's dimension
    3  bulk load nodes, then edges, then vectors from the pinned S3 prefix
    4  run the invariants from schema.md
    5  work
    6  delete the graph
    7  confirm it's gone. check the console, not your memory.

Step 7 is not paranoia. An orphaned graph is the only way this project overruns its budget.

**Graph snapshots** are storage-priced and much cheaper than a running graph, so
snapshot-and-restore is a reasonable shortcut for a mid-week session. Don't let it become the
normal path: rebuild from S3 at least a couple of times a week, or the reconstructibility
claim quietly stops being true and you find out during the demo.

## Rebuilding from zero

The week 1 gate, and the daily reality:

    pick a snapshot prefix   s3://<staging>/osv/raw/PyPI/<stamp>/
    materialize              nodes.csv, edges.csv, chunks.csv (with embedding:vector)
    create graph             with the vector index
    neptune.load()           nodes, then edges
    verify                   counts, checksums, the eight invariants
    replay                   deltas after that snapshot, from the ingest log

Two rebuilds of the same snapshot must produce identical checksums. Sort before hashing —
result ordering isn't guaranteed and an unsorted checksum will flap.

Embeddings survive teardown because they live in the DynamoDB registry keyed by content hash,
not in the graph. A rebuild re-reads them; it doesn't re-pay for them. That's the second
reason the registry exists.

## Snapshots

Already running. `scripts/init-snapshot.ps1` (Windows) or `scripts/init-snapshot.sh`. Daily,
and the one input that can't be backfilled — a missed day is a delta that no longer exists
anywhere.

Objects land under `osv/raw/PyPI/<UTC hour>/`. Bucket name comes from
`/chokepoint/dev/staging_bucket`.

Check weekly that snapshots are actually landing. A cron job that stopped three days ago
looks exactly like a quiet week.

## When something looks wrong

    symptom                          look at
    -----------------------------------------------------------------------------------
    k-NN returns nothing             does the graph have a vector index? were the
                                     embeddings silently dropped at load time?
    ParsingException on load         embedding dimension mismatch. the message names the
                                     line and file.
    duplicate nodes                  MERGE on a property bag instead of ~id. see
                                     knowledge-graph.md.
    AFFECTED_BY count is 0           range evaluation. probably string comparison instead
                                     of PEP 440.
    AFFECTED_BY count is enormous    introduced: "0" treated as "everything", or ranges
                                     evaluated against all of PyPI rather than your
                                     versions.
    every advisory looks changed     diffing modified_id.csv line-wise instead of on the
                                     id column, or trusting modified_at without a field
                                     diff.
    re-ingest calls Bedrock          chunk_key isn't stable. usually whitespace or
                                     markdown normalisation.
    vector with no node              a chained vector + graph write failed halfway. vector
                                     writes are not atomic. the orphan sweep finds these.
    query times out                  unbounded variable-length pattern over a cyclic
                                     dependency graph. bound the depth.
    plan fails on the wrong account  allowed_account_ids did its job. check AWS_PROFILE.

## Teardown at the end

When the project is done: delete the graph, keep the S3 snapshots and the DynamoDB tables.
The snapshots are the evidence base and cost cents; the graph is the expensive part and
regenerates from them in minutes.

Verify the graph is gone. Then verify it again in the console the next morning.
