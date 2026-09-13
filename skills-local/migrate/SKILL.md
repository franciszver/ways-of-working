---
name: migrate
description: Upgrades and migrations in reversible steps — breaking changes read first, one major version at a time, expand-migrate-contract for data. Use for dependency/framework upgrades and schema or data migrations.
---

<!-- local: derived-from: skills/migrate/SKILL.md@ddc573ac67c2 -->

# Migrate Protocol

You are a local model running a migration. Token usage is not a concern — read every changelog. The one property every step must preserve: at any moment you can stop, and the system still works.

## Step 1 — READ FIRST

- Read the changelog/migration guide for EVERY version you cross. The breaking-changes list is the spec.
- Grep the codebase for each deprecated/changed API; write the list of actual call sites — this is your checklist.
- Write the rollback plan BEFORE starting: how to get back from each step; flag any one-way step and schedule it last.

## Step 2 — STAGING RULES

- One major version at a time. v2→v4 is two migrations.
- One dependency per commit/PR. A 40-package lockfile diff is unbisectable.
- Mechanical changes (codemod, rename) in their own commit with zero hand edits; judgment fixes separately.
- Test suite must be green BEFORE the upgrade, or failures can't be attributed to it.

## Step 3 — DATA AND INTERFACES: EXPAND → MIGRATE → CONTRACT

Never change persisted formats or public APIs in place:
1. EXPAND: add the new column/field/endpoint alongside the old. Both work. Deploy.
2. MIGRATE: dual-write / backfill / move readers. Verify counts and spot-check values BEFORE proceeding.
3. CONTRACT: remove the old path only after measurement (logs/metrics) shows nothing reads it, one deploy after you think it's safe.

Check schema changes for table locks against production-sized data, not the dev database.

## Step 4 — VERIFY

- Full suite green + walk the Step 1 call-site checklist one by one.
- Runtime proof, not just compile proof. Deprecation warnings are next year's breakage — resolve or ticket them.
- Data: row counts + sampled field diffs + the application actually reading migrated data. Script exit 0 proves nothing.

## Step 5 — FINISH THE LONG TAIL

Done = the OLD thing is gone: compat shims, dual-writes, pins, "TODO remove after migration". Grep for the old API one final time. Contract step gets a date, never "later".

## Report

Versions crossed + breaking changes that applied · call sites changed (count) · rollback status per step · verification evidence (quoted) · remaining long-tail with date.

## Hard rules

- No refactoring inside the migration commit.
- No "upgrade everything" commits. Every upgrade needs a stated reason.
- Never backfill and contract in the same deploy.
