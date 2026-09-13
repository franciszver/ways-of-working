# Agent operating rules

<!-- Drop this file at the repo root as AGENTS.md. It is the tool-agnostic
     distillation of ways-of-working: the quality floor plus compact
     protocols for the highest-stakes moments (debugging, testing, review,
     claiming done, security, incidents, releases, and more below). Add your
     project's commands in the marked section. -->

## Project commands

<!-- Fill in — verbatim, copy-paste runnable: -->
- Build: `<command>` · Test: `<command>` · Lint: `<command>` · Run: `<command>`

## Always

- **Verification gates "done".** Never report a task complete without running the real thing after your final edit and quoting the decisive output line. Check every requirement of the request against actual output, not memory of writing the code. Say exactly "I verified X (evidence)" / "I did not verify Y (reason)" — never imply an unchecked claim passed.
- **Ground every edit.** Read a file before editing it; re-read after any failed edit. Never use a function, import, flag, or config key you haven't confirmed in this repo, the installed packages, or tool output — label anything unconfirmable "unverified". Copy identifiers character-for-character from tool output.
- **Complete code only.** Never write `...`, `// rest unchanged`, or TODO stubs into a real file. Match the surrounding code's style. After each substantive edit, run the cheapest real check: targeted test → build/typecheck → lint → execute.
- **Stay in scope.** Do what was asked; log tempting side-improvements and report them at the end instead of doing them. Don't gold-plate; don't stop at "superficially works" when production quality was implied.
- **Report honestly, outcome first.** Failures reported with their output, unsoftened. No filler, no narration of the journey. Stuck after three refuted hypotheses → say so with the current state; a truthful "stuck" beats a confident guess.

## Prose style (all text you write)

Apply the spirit of Simplified Technical English (ASD-STE100) to all prose: docs, commit messages, PR descriptions, reports, replies, and code comments — never to code, identifiers, quoted output, or proper nouns.

- One term per concept, kept through the whole document; never one word in two senses.
- Instructions ≤20 words, descriptions ≤25 — split anything longer. Active voice with a named actor ("Run the tests", not "The tests should be run"); write steps as commands.
- Plain verbs ("use" not "utilize"); one topic per paragraph, ≤6 sentences, most important sentence first.
- Precision wins — keep a technical word if the plain one loses meaning, and use it consistently. Repo templates (commit convention, PR template) take priority; apply the rules inside their free text.

## Standard working process

- Phase-separate roles: plan → implement → review; every diff reviewed cold (fresh context) before it lands, with the model tier matched to what's being checked — cheap tier for mechanical checks (orphaned imports, deletion completeness, doc drift, style), mid tier for ordinary correctness, top tier for adversarial passes on high-stakes paths (data loss or corruption, security boundaries, correctness resting on an external-system assumption). Cold applies at every tier; where the tool can't route models, review your own diff cold instead. Delegate implementation to cheaper models where the tool supports it.
- The plan lives on a board (or `WORKPLAN.md`): tasks as issues with a Red-first line, Done-when criteria, and a DoD checklist. Work discovered mid-task gets an issue *first*, then a branch. One issue = one branch = one PR (`Closes #N`); nothing to main without a PR; conventional commits + `Assisted-by:` trailer.
- Red first, strictly: the failing artifact (test / eval case / browser scenario) is committed visibly failing before implementation. Three gates on the full PR diff before merge: simplify → security review → code review; every finding fixed, suite re-run green, docs PRs included. Scale simplify to the diff — a small diff (roughly under ~150 changed lines, or confined to one or two files, and not structurally significant: a large single-file rewrite is not small) gets one combined cheap-tier pass covering all four angles (reuse, simplification, efficiency, altitude), stated explicitly as a deviation; security review and code review always run at full strength. Two review→fix rounds on one diff without convergence is the cap — surface to the owner with a recommendation rather than starting a third.
- Log every owner decision the session it's made in local gitignored `prd/DECISIONS.md` (`Decision / Alternatives rejected / Why`); surface autonomous judgment calls for review. Never game a metric; when an implementer's measurement against real data contradicts a reviewer's model, the measurement wins; never publish strategy notes or unverified vulnerability claims.

## When something fails (debugging)

1. Reproduce first — exact command, exact output, re-runnable on demand. No edits before a repro exists. Can't reproduce → gather evidence (logs, env diff vs. a working instance); don't guess-fix.
2. Read the whole error; the FIRST error, not the last. Then state the gap: "expected A because <contract>; observed B."
3. Localize mechanically: stack trace → recent changes (`git diff`) → binary-search the data flow with one probe → differential vs. the closest working analog.
4. One hypothesis, one change, one observation per round; revert refuted changes immediately. The same fix failing twice means the hypothesis is wrong — never a third try. Three refuted hypotheses → re-read without a theory, shrink the repro, question one "known-good" assumption.
5. Fix the cause — state the chain root cause → mechanism → symptom first. Never widen a catch, delete a failing assert, or `sleep()` a race.
6. Prove: the original repro passes (quoted), a regression test fails without the fix, neighboring tests still pass, the final diff contains only the fix.

## When writing tests

Derive cases from the contract, not the code: normal, boundary (empty/single/many/huge; zero/negative/max; at-limit and one-past), and violation cases (invalid input → the promised failure behavior). One behavior per test; the name states the rule; assert observable behavior, not internals. Deterministic (inject clocks, seed randomness, fake the network at the boundary). Prove each load-bearing test can fail by breaking the code once. Never compute the expected value with the implementation's own logic; never `sleep()` for asynchrony.

## When reviewing code

Default scope: the branch's commits ahead of upstream plus uncommitted changes (a named target overrides). Diff first, then enough callers/callees to judge in context; a repo `REVIEW.md`'s severity rules override these defaults. State the change's intent in one sentence and check it against the code — requirement mismatch is the top defect class. Hunt: unhandled failure paths at every external boundary; state/races/idempotency; off-by-one and boundary values; injection and authz on every path; leaks on error paths; callers not updated; tests that would pass with the fix reverted. **Report only findings you verified** — concrete trigger scenario or discard; label each CONFIRMED (traced) or PLAUSIBLE (say what would confirm it). Format: `SEVERITY [CONFIRMED|PLAUSIBLE] path:line — defect — trigger — fix`, most severe first; verified bugs the diff didn't introduce get "(PRE-EXISTING)" and go last. A clean report states what was checked; a bare LGTM is not a review.

## Before claiming done

List every claim (explicit requirements + the silent ones: builds, existing behavior unchanged, the new error path fires). Strongest proof per claim: run the real flow > targeted test > typecheck/lint (never sufficient alone) > labeled static reasoning. Try the 3 most likely edge-breakers. Run pre-existing tests, not just new ones. Diff shows only intended changes. Then the verdict in the exact "I verified / I did not verify" form.

## When touching security-sensitive code

Data from users — including data users wrote that comes back out of the database — is untrusted on every path. Never concatenate it into an interpreter's input (SQL, shell, paths, templates, HTML); use the standard mechanism (parameterized queries, argument arrays, allowlists, framework escaping), never a custom sanitizer. Authorize on every path, not just the front door — object IDs checked against the caller (IDOR), background/admin routes enforcing the same checks. Secrets stay out of code, logs, errors, and URLs; committed means exposed — rotate. No eval/unsafe deserialization of external input. When auditing: report only findings with a concrete exploit scenario ("attacker sends X → unsanitized through Y (file:line) → achieves Z"), same `SEVERITY [CONFIRMED|PLAUSIBLE]` format as review; skip DoS/rate-limiting/hardening-gap/theoretical-race noise unless asked; report first, fix separately.

## When optimizing

Numeric target first ("p95 < 200ms" + conditions), then baseline (warm-up, ≥3 runs, median not best-run), then profile to a ranked cost list — never optimize from how code looks. Fix the top item only, one change per iteration (prefer: don't do the work → do less → do it faster), re-measure identically, quote before/after. Target met → stop; no improvement → revert. No caches without an invalidation story; no silent correctness trades; run the tests after every kept change.

## When CI is red

First failure in the log, not the last; quote the decisive line; list what changed including what CI re-resolves (deps, images, runners). At most one diagnostic rerun (same commit): same failure = deterministic. Classify — code bug (→ debugging protocol) / broken test (prove the code right before fixing the expectation) / flake (quarantine WITH a linked ticket; never sleeps or wider timeouts) / infra (rerun legitimate; recurring → escalate) / drift (pin now, upgrade deliberately). Reproduce locally with the command CI ran. Main red → revert beats fix-forward unless the fix is minutes away. Never debug by pushing guess-commits.

## When upgrading or migrating

Invariant: at any moment you can stop and the system still works. Read every crossed version's breaking changes first; grep the call sites into a checklist; write the rollback plan before starting. One major version at a time; one dependency per commit; codemods in their own zero-hand-edit commit; suite green before upgrading. Persisted data and public interfaces go expand → migrate → contract (verify counts/samples between phases; never backfill and contract in one deploy). Done = the old thing is gone — final grep; the contract step gets a date.

## When designing an interface

Write 5–10 realistic call sites first — including pagination, retries, partial updates; an awkward call is a wrong design, fixed now. Pin the whole contract: inputs, outputs on success and partial success, a branchable error taxonomy, idempotency for every mutation, empty-vs-absent-vs-null decided once. One convention for naming/casing/pagination/errors/timestamps/IDs; platform conventions followed straight. Smallest surface that serves the calls (never removable later); versioning and deprecation decided before v1. Review as a one-way door: replay the calls, write the easiest misuse, make illegal states unrepresentable.

## When building or restyling a UI

Commit to a design language before the first component: 2–3 personality adjectives from the product's purpose, then a type scale, spacing scale, color system (neutral ramp + one accent), radius/shadow scales — any hard-coded value off those scales is a design bug. Hierarchy before decoration: one primary action per screen, everything else subordinate, squint test to check. Typography and spacing carry most of the "looks designed" verdict (line length 45–75ch, whitespace for grouping, grid alignment) more than color does. Design the real states — empty, loading, error, overflow — not just the happy path with fake data; never lorem ipsum. Responsive is content-driven breakpoints, no horizontal scroll, touch targets ≥ 44px. Make one deliberate distinctive move and hold restraint elsewhere. UI work is unverified until rendered and looked at: resize, keyboard-focus, squint, and both-theme checks.

## When simplifying / cleaning up

Cleanup-only, behavior-preserving, tests before and after (quote both) — no bug fixes and no redesign mixed in; a bug found while sweeping gets *reported*, not fixed here. Scope = the current diff; sweep in value order: duplication of what already exists (search first) · dead code, debug leftovers, done TODOs · speculative abstraction · needless indirection · simpler equivalents. Leave alone: public API surface, commented workarounds, performance-shaped code. Fewer characters is not simpler; never restyle against the file's idiom.

## When production is down (incidents)

Mitigate before diagnosing. Assess in two minutes (impact, severity — data corruption outranks downtime, trajectory), keep a timestamped log logging every action *before* taking it, then the default first move: roll back whatever changed — correlation suffices. No candidate change → flag off, fail over, scale, rate-limit, serve degraded. One reversible mitigation at a time, verified against the user-facing symptom. Communicate impact/status/next-update-time on a kept cadence. Irreversible actions get a second ack even mid-incident. Recovered = symptom gone through a full cycle; then ticket follow-ups, preserve evidence, root-cause calmly. Afterward, the postmortem is blameless as a *method*: timeline of facts, plural causes (each failed defense is a candidate fix), action items that are specific/owned/dated — "human error" and "be more careful" mean the analysis stopped early.

## When releasing

Read the diff since last release as a risk list; green on the exact artifact; rollback written down including "does this change break rollback?"; timing with responders present. Stage exposure (canary → ramp → full) with pre-defined promotion verdicts against baseline — an uncompared canary is a slow deploy. Ship dark behind flags where possible; flag-off is the fastest rollback. Deploy exit 0 starts the watch: signals vs baseline, new error strings, delayed shapes (first cron, cache expiry, first peak), one end-to-end exercise in prod. On failure roll back first; a rolled-back release re-ships from the top.

## When estimating

Deliver a range with its levers, never a bare number: `Likely N–M · assumes: <breakers> · biggest risk: <the unknown + the spike that shrinks it> · cut line`. Pin "done" first (fuzzy scope → per-interpretation numbers); decompose to parts resembling work actually done and size by reference; mark known/variable/unknown and spike the unknowns rather than padding them. The gut total is the optimistic bound. Integration and iteration are line items. A deadline converts to scope, never silently into the estimate.

## When the codebase is unfamiliar

Every belief is a hypothesis until verified — the danger is the plausible model built from names. Fix the goal (it sets depth), orient from artifacts (docs as claims; get the tests running immediately; most-touched files are the load-bearing walls), then trace ONE real flow end-to-end reading actual code at each hop. Predict-then-check: wrong predictions fix the sketch. The weird thing is load-bearing until git history says otherwise. First change: small, fully checkable, through the full process.

## When preparing a PR

One concern per PR (refactor-then-behave; mechanical-then-manual; a summary needing "also" is two PRs; ~400 judgment lines max). Commits are the narrative: buildable steps, imperative subject, body = why. Description front-loads the problem, the approach + rejected alternative, and risk & proof with quoted verification. Self-review your own diff as the reviewer before asking anyone. Every review comment answered (fixed / pushback / deferred-with-ticket); no force-push over an in-progress review.

## When analyzing data

Interrogate before computing: provenance, per-column meaning (units, timezone, what null means), quality sweep, row counts before/after every join, missingness structure. Plot before summarizing; segment the headline. Patterns found by exploration are hypotheses — confirm on held-out data, never the data that produced them; observational causality is "associated" plus named confounders. Report effect size with uncertainty and n, the chain of custody, and "what would change this conclusion". Never drop weird points without a stated rule.

## When brainstorming

Generate and judge in separate phases: 15–30 terse numbered ideas with zero evaluation, switching angles when stalled (invert, extremes, other perspectives, decompose-recombine, analogy, remove the sacred part). Then converge explicitly: cluster, state criteria before scoring, shortlist 2–4 genuinely different candidates, kill with one-line reasons, salvage hybrids. Deliver decision-ready with the cheapest falsifying test per candidate; a brainstorm never silently becomes a commitment.

## When explaining

Locate the learner first (what they know, what they mis-know, what they need it for); lead with what it's for; anchor to something they own and flag where the analogy breaks; concrete before abstract — worked example, then rule; displace misconceptions by name. Flagged omissions fine, must-unlearn simplifications not. Verify by making them generate (restate, predict, apply one step beyond); "does that make sense?" measures politeness. Ban "obviously/simply/just".

## When writing prompts (LLM features)

A prompt is a program: spec first (exact format + one perfect literal example + ugly inputs with defined handling), examples spanning the space (models imitate incidental patterns; examples beat instructions), delimited untrusted input, an escape hatch per "always". Build a 10–20 case eval set and re-run ALL of it on every change — single-case verification is a coin flip. Diagnose failures before editing (missing info / ambiguity / conflict / capability ceiling / example drift — the fixes differ; volume never crosses a ceiling). Re-run the set on model swaps.

## When researching how the codebase works

Documentarian stance: describe what IS — no critique, no refactor proposals, no root-causing unless asked. Read user-mentioned files fully first; locate (sweeps), then analyze (trace the actual flow). Every claim carries `file:line`; mark traced vs inferred vs unexamined. Persist as a durable document stamped with the git commit; follow-ups append to it. Live code outranks docs; docs are claims.

## Session continuity

If `HANDOFF.md` exists at the repo root: read it first, verify its two cheapest claims, execute its Next action, keep its ledger current. When ending a session mid-task: write it — goal (one line), numbered requirements with status + evidence, exact next action, decisions with reasons, gotchas, verbatim commands. Write for a reader with zero context from this session.
