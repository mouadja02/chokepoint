# 9. Typed agent tools, no raw query access

Date: 2026-08-27
Status: Accepted

## Context

The agent needs to query the graph. Two approaches: expose a `run_cypher(query: str)` tool
and let the model write queries, or expose a fixed set of typed tools that each run a query
you wrote.

Text-to-Cypher demos well. It also looks like more capability for less work.

## Decision

Five typed tools — `list_exposures`, `explain_path`, `search_advisories`, `what_changed`,
`best_upgrade` — with typed arguments and typed returns. No raw query tool, at any point, in
any form.

## Consequences

- **Evaluation means something.** A wrong answer is a bug in one query you own. With generated
  queries, a regression could be the model, the prompt, the schema or the data, and the golden
  set stops being a regression suite and becomes a sample of today's model behaviour.
- **No injection surface.** Read-only credentials would limit the damage, not remove it: an
  unbounded traversal is a denial of service against a memory-resident engine billed by the
  hour.
- **Every traversal is bounded.** Depth limits, `LIMIT`, timeouts and explicit `ORDER BY` are
  written once, by hand, in queries that don't change between runs.
- **It forces the modeling work.** Deciding which five questions the graph answers is the
  design. Text-to-Cypher is a way to avoid making that decision, and the decision is the part
  worth demonstrating.
- The agent can't answer questions nobody anticipated. That's the real cost, and the answer is
  that unanticipated questions should produce an abstention, not a guess — which the golden
  set measures directly (`evaluation.md`).
- Adding a capability means writing a tool, not prompting harder. Slower per feature, and
  every feature arrives with a test.
