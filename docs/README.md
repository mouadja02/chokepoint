# docs

Written before the code, so the code has something to disagree with.

Read in this order:

    glossary.md          the words. start here if "ontology" and "LPG" are new
    ontology.md          how to design the model, and how this one was derived
    schema.md            the model itself. normative -- the loader enforces this
    knowledge-graph.md   ontology -> a loaded graph: identity, idempotency, loading
    deltas.md            keeping it current. the part that is actually hard
    agent-tools.md       the five tools, and why there is no sixth
    evaluation.md        how you prove any of it works
    runbook.md           create, load, tear down, and what it costs per hour

    adr/                 decisions, with the reasoning attached

The spec (`chokepoint-project-spec.md`, not committed) says what to build and by when.
These say how, and why it ended up this shape.

None of it is code. Where a query or a record appears it's there to pin down a shape,
not to be pasted.

## If you only read two things

`ontology.md` sections "The five questions" and "Time, and facts that stop being true",
then `deltas.md`. Everything else is downstream of those.
