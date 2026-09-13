---
name: api-design
description: Designs interfaces from the consumer's side — writes the calls you wish existed, makes the contract explicit including errors, plans evolution before v1 ships. Use when designing or reviewing an HTTP/RPC API, a library's public surface, a CLI, an event schema, or any boundary other people's code will depend on.
---

# API Design Protocol

You are a local model designing an interface others will depend on. Token usage is not a concern. An API is a promise you can't unmake — every quirk becomes load-bearing — so the effort goes in before first release.

## Step 1 — WRITE THE CALLS FIRST

Write 5–10 realistic call sites verbatim, as the consumer would write them, INCLUDING the annoying cases: pagination loop, retry after failure, partial update, error handling. Awkward call site = wrong design, fix it now. Only then derive the interface that makes those calls true. Name the primary consumer and design for them.

## Step 2 — PIN THE CONTRACT

For each operation write down:
- Inputs: types, units, ranges, required/optional, behavior on invalid
- Outputs: success shape AND partial-success shape (some items failed → what?)
- Errors: a small stable taxonomy the caller can branch on (machine-readable code + human detail). Separate caller-can-fix / caller-should-retry / caller-can't-help
- Semantics: idempotency for every mutating operation (retries happen), timeouts, pagination stability, concurrent-update behavior
- Emptiness: empty list vs absent vs null — one meaning each, everywhere

## Step 3 — CONSISTENCY BEATS CLEVERNESS

One naming convention, one casing, one pagination scheme, one error shape, one timestamp format (ISO 8601 UTC), one ID type — inside the API. Follow the platform's conventions outside it (HTTP verbs/status codes straight; your language's stdlib idioms). Novelty in an API is a defect unless it pays for itself.

## Step 4 — PLAN EVOLUTION BEFORE V1

- Ship the SMALLEST surface that serves the Step 1 calls. You can add; you can never remove. In doubt → leave it out.
- Adding optional fields is safe only if consumers ignore unknowns — state that expectation in the contract.
- Pick the versioning mechanism now (URL/header for HTTP; semver for libraries) and the deprecation promise (how long, what warning, what migration doc).

## Step 5 — REVIEW AS A ONE-WAY DOOR

- Re-read each Step 1 sample call against the final design.
- Write the easiest MISUSE a consumer could make; redesign so illegal states are unrepresentable where possible.
- Check every error path has a defined shape.
- Extending an existing API: its existing conventions win over your preferences, even ugly ones.

## Deliverable

The operations/contract table · runnable sample calls (keep them tested) · versioning + deprecation policy · explicit non-goals ("does not support X"). HTTP → OpenAPI file beats prose.

## Hard rules

- Never design outward from the database schema.
- No god endpoint with a mode parameter — split it.
- No booleans that will grow a third state — enum from day one.
- Errors are never strings-to-parse and never 200-with-error-body.
