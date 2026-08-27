# 14. A single Terraform state

Date: 2026-08-27
Status: Accepted

## Context

The infrastructure is a VPC, an S3 bucket, two DynamoDB tables and some SSM parameters, in one
account and one region. The conventional layout splits state per environment, sometimes per
component, to limit blast radius and let pieces deploy independently.

There's one environment, one person, and a three-week life expectancy.

## Decision

One state file, `chokepoint.tfstate`, in `chokepoint-tfstate`. Everything under `infra/` is a
single stack. Backend config is committed at `infra/config/backend.conf`; it holds no secrets.

## Consequences

- One `plan` shows the whole picture. No cross-state data lookups, no remote state
  dependencies, no ordering between stacks.
- Blast radius is the whole project. Acceptable when the whole project is one person's demo
  and every resource in it is rebuildable.
- Splitting later is a `terraform state mv` exercise, not a rewrite.
- The state bucket itself can't be managed by this state — Terraform can't bootstrap its own
  backend — so it was created by hand, and its lifecycle rule is applied out of band from
  `infra/config/tfstate-lifecycle.json`.
- `use_lockfile = true` on a versioned bucket writes and deletes a lock object per operation,
  leaving a version and a delete marker behind every time. Half an hour of work left twenty.
  The lifecycle rule expires noncurrent versions after a day, which means state history only
  goes back a day — an acceptable trade for a project whose resources are all disposable.
- The provider pins `allowed_account_ids`. This machine has credentials for two accounts and
  `AWS_PROFILE` often points at the wrong one; the pin turns that into a failed plan instead
  of resources created somewhere they don't belong.
