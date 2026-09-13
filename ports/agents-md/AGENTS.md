# Agent operating rules

<!-- Drop this file at the repo root as AGENTS.md — the single portable
     entry point for every tool. Tools that expand `@` paths pull in the
     linked SKILL.md on demand; a tool that does not expand `@` paths
     should open the file at that path directly when its trigger matches. -->

## Project commands

<!-- Fill in — verbatim, copy-paste runnable: -->
- Build: `<command>` · Test: `<command>` · Lint: `<command>` · Run: `<command>`

## Always

- **Verification gates "done".** Run the real thing after your final edit and quote the decisive output line. Check every requirement against actual output, not memory. Say exactly "I verified X (evidence)" / "I did not verify Y (reason)" — never imply an unchecked claim passed.
- **Ground every edit.** Read a file before editing it; re-read after a failed edit. Never use a function, import, flag, or config key not confirmed in this repo, its installed packages, or tool output — label the unconfirmable "unverified". Copy identifiers character-for-character from tool output.
- **Complete code only.** Never write `...`, `// rest unchanged`, or TODO stubs into a real file. Match the surrounding style. After each substantive edit, run the cheapest real check: targeted test → build/typecheck → lint → execute.
- **Stay in scope.** Do what was asked; log tempting side-improvements and report them at the end instead of doing them. Don't gold-plate; don't stop at "superficially works" when production quality was implied.
- **Report honestly, outcome first.** Failures reported with their output, unsoftened. No filler, no narration of the journey. Stuck after three refuted hypotheses → say so with the current state; a truthful "stuck" beats a confident guess.
- **Write steps as commands, with plain verbs.** "Run the tests", not "The tests should be run"; "start", not "initiate".
- **Resume from a handoff.** If `HANDOFF.md` exists at the repo root, read it first.

## Skills

Each line points at one canonical skill's full protocol. Load the file at its path when the task at hand matches the trigger; a tool that does not expand `@` paths opens the file directly.

<!-- gen-ports:skills:begin -->
- @skills/api-design/SKILL.md — Use when designing or reviewing an HTTP/RPC API, a library's public surface, a CLI, an event schema, or any boundary other people's code will depend on.
- @skills/apply-working-process/SKILL.md — Use when starting work in a repo, planning a feature, or before the first edit of a session in a project.
- @skills/architect/SKILL.md — Use when designing a system or feature, choosing between technologies or approaches, writing a design doc or ADR, or making any decision that is expensive to reverse.
- @skills/brainstorm/SKILL.md — Use when asked to brainstorm, generate options/names/approaches, find alternatives to a stuck plan, or when a decision is being made with only one candidate on the table.
- @skills/breakdown/SKILL.md — Use when planning a multi-step feature or project, splitting work for parallel agents or sessions, or when a task is too big to hold in one context window.
- @skills/ci-triage/SKILL.md — Use when CI fails, a pipeline breaks, a build goes red, or a test is flaky.
- @skills/data-analysis/SKILL.md — Use when exploring a dataset, answering a question with data, building metrics/dashboards, evaluating an experiment, or checking someone else's numbers.
- @skills/debug/SKILL.md — Use whenever anything fails — bug report, failing test, error message, stack trace, regression, flaky behavior, or "it worked yesterday".
- @skills/declutter/SKILL.md — Use as a quality gate before opening a PR, after generated/AI-written code, or when asked to simplify/clean up recent changes.
- @skills/deep-review/SKILL.md — Use when asked to review code, a diff, a branch, or a PR; before merging significant work; or to attack your own completed work with fresh hostility.
- @skills/demo-video/SKILL.md — Use when asked to make a demo video/gif of an application, a walkthrough recording, or a README hero animation.
- @skills/estimate/SKILL.md — Use when asked how long/how big/how much effort something is, when scoping or prioritizing work, or when a deadline is being negotiated.
- @skills/explain/SKILL.md — Use when teaching a concept, explaining how something works or why a decision was made, answering "what does this mean", writing tutorials/onboarding docs, or mentoring.
- @skills/frontend-design/SKILL.md — Use when building or restyling any UI — web app, landing page, dashboard, component library — or when a working interface "looks off" and needs design quality.
- @skills/handoff/SKILL.md — Use when context is running long, when ending a session mid-task, when downshifting work to a smaller model, or when delegating a subtask.
- @skills/incident/SKILL.md — Use when production is down or degraded, users are impacted, an alert is firing, or "something is wrong in prod" — before any root-cause work.
- @skills/lean-max-effort/SKILL.md — Use when a task spans multiple steps, files, or tool calls, or when the user asks for thoroughness, tokens, budget, or efficiency.
- @skills/migrate/SKILL.md — Use for dependency/framework/language upgrades, API version bumps, database schema or data migrations, and platform moves.
- @skills/onboard/SKILL.md — Use when joining a project, picking up an unfamiliar repo/service/module, or before making changes in code you've never touched.
- @skills/perf/SKILL.md — Use when something is slow, uses too much memory, or costs too much; when asked to optimize; or when setting performance budgets.
- @skills/plain-language/SKILL.md — Use whenever prose will be read by a person, especially anything shipped publicly (docs, README, UI copy, PR and issue text, emails, applications).
- @skills/postmortem/SKILL.md — Use after an incident, outage, data loss, near-miss, or any "how did that happen" retrospective.
- @skills/pr-workflow/SKILL.md — Use when creating branches/commits/PRs, preparing work for review, splitting an oversized change, or responding to review.
- @skills/prompt-eng/SKILL.md — Use when writing or debugging prompts, system prompts, agent instructions, or LLM-powered features; when a model's output quality is the problem to solve.
- @skills/prove/SKILL.md — Use before reporting any task complete, before commits and handoffs, after fixes, and whenever the user asks "does it work?".
- @skills/refactor/SKILL.md — Use when restructuring, extracting, renaming, moving, de-duplicating, or modernizing code, or when asked to "clean up" working code.
- @skills/release/SKILL.md — Use when deploying, releasing, publishing a package, running a launch, flipping a major feature flag, or writing a release/deploy checklist.
- @skills/research/SKILL.md — Use for any research task — technical evaluations, "which X should we use", market/landscape questions, fact-finding, due diligence — and before answering factual questions where being wrong is costly.
- @skills/research-codebase/SKILL.md — Use when asked how something works, where something lives, what the current behavior is, or to research/document a codebase area before planning changes.
- @skills/sec-audit/SKILL.md — Use when asked for a security review/audit, before shipping auth/payment/user-input handling code, or when handling data from untrusted sources.
- @skills/spec/SKILL.md — Use when requirements are fuzzy or contradictory, when scoping a feature, or when asked for a spec.
- @skills/ste-writing/SKILL.md — Use whenever writing prose a person will read: docs, commit messages, PR text, reports, replies, code comments.
- @skills/testgen/SKILL.md — Use when writing or improving tests, adding regression tests after a fix, or when asked to "add test coverage" for existing code.
- @skills/write/SKILL.md — Use for any prose deliverable — docs, READMEs, design docs, proposals, reports, announcements, emails, tutorials — whenever the writing itself is the product rather than a byproduct.
<!-- gen-ports:skills:end -->
