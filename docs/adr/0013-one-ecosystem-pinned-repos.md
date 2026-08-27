# 13. One ecosystem, deliberately pinned repos

Date: 2026-08-27
Status: Accepted

## Context

The graph could cover PyPI, npm, Maven, Go and more; OSV publishes all of them. And the
"repos" could be real personal projects rather than constructed ones.

Three and a half weeks. The judgement is on the depth of the delta handling, not on corpus
size, and every ecosystem added is another resolver, another version ordering scheme, another
set of range semantics.

## Decision

PyPI only. Five dependency sets built deliberately and pinned to older versions:

    web-api        fastapi + uvicorn + pydantic + httpx, ~12 months back
    legacy-django  django + celery + redis, ~24 months back
    ds-notebook    pandas + numpy + scikit-learn + jupyter
    ml-train       torch + transformers + datasets
    cli-tool       click + requests + rich

## Consequences

- One version ordering scheme to get right: PEP 440. Adding npm would mean semver as well,
  with different range syntax and different edge cases, and version comparison is where
  correctness in this project actually lives.
- Guaranteed real exposures. Pinning to older versions means the graph isn't all-green, which
  a snapshot of current best-practice repos very likely would be.
- Ground truth is verifiable by hand. Five sets of a few dozen packages can be checked against
  `pip show`, which is what makes the golden set trustworthy.
- **Dependency churn becomes controllable.** "I upgraded a package" is a delta triggered by
  editing one line, whenever a test needs it. Advisory churn comes from the world; dependency
  churn comes from you; between the two, every delta type is reachable on demand without
  waiting for anything.
- Not personal repos, so the "point it at your own code" story is weaker. Recoverable in a
  demo by adding one real lockfile at the end — the pipeline doesn't care where a lockfile
  came from.
- Nothing proves the model generalises to npm. Worth saying honestly: the model is
  ecosystem-shaped, and `Version` ordering is the part that would need work.
