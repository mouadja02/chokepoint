# 1. Record architecture decisions

Date: 2026-08-27
Status: Accepted

## Context

This project makes a dozen choices that are hard to reverse — a graph engine, a query
language, a data model, a deletion semantic — in three and a half weeks, mostly alone. In
three months the reasoning will be gone, and the most likely question anyone asks about any
of it is "why did you do it that way".

The alternative to writing them down is reconstructing them from the code, which produces
plausible reasoning rather than actual reasoning.

## Decision

Keep architecture decision records in `docs/adr/`, numbered, in Michael Nygard's format:
context, decision, consequences. One decision per file. Immutable once accepted; a changed
mind is a new ADR that supersedes the old one.

Record the alternatives that were rejected and why, not only the choice.

## Consequences

- The rejected alternatives are recorded, which is the part that's actually asked about.
- Some ADRs will be short and obvious in hindsight. Write them anyway — hindsight is exactly
  the thing that isn't available later.
- ADRs go stale if edited to match reality. They aren't documentation of the system; they're
  a record of decisions at a point in time. `docs/*.md` describes how things are now.
- Overhead is a few minutes per decision, and only for decisions that are hard to reverse.
  Nothing about naming conventions or file layout belongs here.
