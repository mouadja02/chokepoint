# Agent tools

Five tools, typed arguments, no raw query access. The interesting design work is in what
they refuse to do.

## The five

    list_exposures(repo: str, min_severity: Severity = LOW) -> list[Exposure]
    explain_path(repo: str, advisory_id: str)               -> list[Path]
    search_advisories(question: str, k: int = 5)             -> list[AdvisoryHit]
    what_changed(since: datetime, repo: str | None = None)   -> list[Change]
    best_upgrade(repo: str)                                  -> list[UpgradeCandidate]

Each maps to one traversal or one query. If a tool needs three unrelated queries and a
branch, it's two tools.

### list_exposures

    MATCH (r:Repo {`~id`: $repo})-[:DECLARES]->(v:Version)
          -[:DEPENDS_ON*0..8]->(dep:Version)-[:AFFECTED_BY]->(a:Advisory)
    WHERE a.cvss_score >= $min_score
    RETURN DISTINCT a, dep

`*0..8` rather than `*` — dependency graphs contain cycles in practice, and an unbounded
variable-length pattern over a cyclic graph is how you discover your query timeout setting.
Bound every traversal.

Returns the advisory *and* the version that brought it in. An exposure without the offending
package is an answer nobody can act on.

### explain_path

The one that justifies the architecture. Return the whole path, not a boolean:

    MATCH p = (r:Repo {`~id`: $repo})-[:DECLARES]->(:Version)
              -[:DEPENDS_ON*0..8]->(:Version)-[:AFFECTED_BY]->(:Advisory {`~id`: $advisory})
    RETURN p ORDER BY length(p) LIMIT 5

Shortest first, capped. There are often several paths to the same advisory and the short one
is the explanation; the rest are noise. Render it as the chain, with the `direct` flag on the
first hop, because "you asked for this" and "this came along" are different problems with
different fixes.

### search_advisories

The vector leg. Embed the question with the same model and dimension as the corpus, then:

    CALL neptune.algo.vectors.topK.byEmbedding($embedding, {topK: $k})
    YIELD node, score
    MATCH (a:Advisory)-[:HAS_CHUNK]->(node)
    RETURN a, node.text, score

Note the older `topKByEmbedding` / `topKByNode` spellings are deprecated in favour of
`topK.byEmbedding` / `topK.byNode`. Same for `distance.byNode` and `distance.byEmbedding`.

This tool answers questions about *prose* — "is it exploitable without auth", "does it need a
crafted request". It must not be the thing that answers "am I affected". If the agent reaches
for it on a structural question, the tool description is wrong, not the model.

Rule for the description: say what the tool knows, and say what it doesn't. "Searches
advisory descriptions. Does not know which repos are affected."

### what_changed

Reads the DynamoDB ingest log, not the graph. That's the whole point — a withdrawn advisory
is gone from the graph, so the graph can't tell you it left.

    query ingest-log GSI where ecosystem = 'PyPI' and applied_at > :since

Then filter by repo if asked, which needs the affected versions from the log row's `detail`,
not a graph lookup — by the time you're asking, the edges are gone.

### best_upgrade

The chokepoint. First thing on the cut list; also the most interesting if you get there.

Brute force is correct and fast enough at this size. For each `Package` with at least one
exposed version, for each candidate newer version:

    exposures_removed = current exposed paths through that package
                        minus exposures the candidate version itself carries
    rank by removed, tie-break on smallest version jump

Two things that make it honest rather than a demo:

- **The candidate must not introduce new exposures.** An upgrade that clears three advisories
  and adds two is not an upgrade. You need `AFFECTED_BY` for the target version, which means
  the target version must be in the graph — so materialise a few versions per package, not
  just the installed one.
- **Verify by brute force on a small repo.** Compute it by hand for one repo with three
  exposures. If the tool and the hand calculation disagree, the tool is wrong.

The reason this is a graph problem and not a SQL one: "paths dominated by a version bump"
is set cover over traversals. It doesn't decompose into rows.

## Why there is no run_cypher

The tempting sixth tool is `run_cypher(query: str)`. It would make the agent look capable
immediately, and it's the wrong call:

- **It's an injection surface.** The LLM writes the query; the query runs against your graph.
  Read-only credentials shrink the blast radius, they don't remove it — an unbounded traversal
  is a denial of service against a memory-resident engine you're paying for by the hour.
- **It makes evaluation meaningless.** When a tool answers, you can test the tool. When a
  generated query answers, you're testing today's sampling of the model. Your golden set
  stops being a regression suite.
- **It hides the modeling.** Typed tools force you to decide what questions the graph
  supports. That decision *is* the design work, and text-to-Cypher is the way to avoid doing
  it.
- **Failures become unattributable.** A wrong answer from `explain_path` is a bug in one
  query you own. A wrong answer from generated Cypher could be the model, the schema, the
  prompt, or the data, and you'll spend the debugging time proving which.

The counter-argument worth acknowledging: typed tools can't answer questions you didn't
anticipate. True. The response is that the five competency-question families cover the
domain, and an unanticipated question should produce an abstention, not a guess. Which is the
next section.

## Routing and abstention

Give the agent a rule, in the system prompt, that mirrors the model:

    structure  -> graph tools     which, whether, how many, why, through what
    prose      -> search          how, under what conditions, does it require
    history    -> what_changed    since, still, any more, changed

And an explicit abstention instruction: if no tool covers the question, say so and name what
you'd need. Abstention is measured in the golden set — see `evaluation.md` — because an agent
that answers everything is an agent that fabricates, and "I can't determine that from the
graph" is a correct answer that most demos can't produce.

Two failure patterns to watch for once it's running:

- **Reaching for `search_advisories` when the answer is structural.** The vector tool always
  returns something, so it's the path of least resistance. Fix the tool description before
  you fix the prompt.
- **Reporting an exposure it found in prose.** Advisory text mentions package names. A
  retrieved chunk saying "affects requests < 2.31" is not evidence that *your* repo is
  affected. The tools must keep those separate, and the answer must cite which tool it came
  from.

## Guardrails

- **Read-only credentials for query tools.** The agent never writes to the graph. Ingestion
  is a separate role.
- **Cap every traversal**: depth bound, `LIMIT`, query timeout. A runaway traversal on a
  memory-resident engine is a cost incident.
- **Cap result size before it reaches the context.** 25,000 advisories exist; no answer needs
  more than a page of them.
- **Log the tool calls with arguments.** When an answer is wrong you need to know which tool
  was asked what. This is also most of your demo.
- **Deterministic tools.** Same graph, same arguments, same result — including ordering. Add
  an explicit `ORDER BY` to every query that returns a list, or your golden set will flap.
