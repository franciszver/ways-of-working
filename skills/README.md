# skills/ — canonical skills (source of truth)

Judgment-dense skills tuned for frontier models (Opus, Sonnet) in Claude Code. Each is a directory with a `SKILL.md`; each doubles as a slash command (`/debug`, `/prove`, …). Compact local-model variants live in [`../skills-local/`](../skills-local/) — install one profile per setup, not both.

## Catalog

### Core process

`lean-max-effort`, `apply-working-process`, and `ste-writing` are also always-on layers via `claude-md/` — installed once per machine, they apply even when no skill fires. The triggers below are their task-shaped invocation points within a session.

| Skill | One line | Reach for it when |
|---|---|---|
| [`lean-max-effort`](lean-max-effort/) | Process backbone: Capture → Plan → Execute lean → Verify | A task spans multiple steps, files, or tool calls, or the user asks for thoroughness, tokens, budget, or efficiency |
| [`spec`](spec/) | Requirements ledger + acceptance criteria + non-goals | Requirements are fuzzy, or before sizable work |
| [`architect`](architect/) | Options, tradeoffs, one-way doors, ADRs | Designing, or any hard-to-reverse decision |
| [`breakdown`](breakdown/) | Decompose into verifiable tasks with DoDs and contracts | Multi-session/multi-agent work |
| [`debug`](debug/) | Hypothesis-driven debugging, no shotgun | Anything fails |
| [`deep-review`](deep-review/) | Verified, severity-ranked findings only | Reviewing a diff/PR, or attacking your own work |
| [`prove`](prove/) | Evidence before "done"; I-verified / I-did-not-verify | Before reporting completion, committing, handing off |
| [`refactor`](refactor/) | Behavior-preserving steps under a test net | Restructuring working code |
| [`testgen`](testgen/) | Tests that hunt bugs, proven able to fail | Writing/improving tests, regression tests |
| [`research`](research/) | Triangulated sources, citation log, disconfirmation | Evaluations, landscape questions, costly facts |
| [`write`](write/) | Audience → thesis → outline → draft → one revision pass | Prose is the product |
| [`handoff`](handoff/) | Continuation brief a cold session can resume from | Context pressure, session end, model downshift |
| [`apply-working-process`](apply-working-process/) | The owner's standard operating process — roles, board-as-plan, red-first, three gates, decision log | Starting work in a repo, planning a feature, or before the first edit of a session in a project |
| [`ste-writing`](ste-writing/) | Simplified Technical English spirit for all prose — one word per idea, short active sentences | Writing prose a person will read: docs, commit messages, PR text, reports, replies, code comments |
| [`plain-language`](plain-language/) | Read a draft against the published signs of AI writing and strike what matches | Before shipping any prose a person will read |

### SE gaps

| Skill | One line | Reach for it when |
|---|---|---|
| [`sec-audit`](sec-audit/) | High-confidence vuln report with concrete exploit scenarios | Security review, before shipping auth/payment/input-handling code |
| [`perf`](perf/) | Profile-first optimization to a numeric target | Something is slow/expensive; performance budgets |
| [`ci-triage`](ci-triage/) | Red-build triage — classify, reproduce, fix or quarantine | CI fails, build is red, test is flaky |
| [`migrate`](migrate/) | Reversible upgrades and migrations, expand→migrate→contract for data | Dependency/framework/language/schema migrations |
| [`api-design`](api-design/) | Consumer-first interface design, full contract before v1 | Designing or reviewing an API, library surface, CLI, event schema |
| [`frontend-design`](frontend-design/) | Designed, not defaulted — tokens, hierarchy, real states, verify by looking | Building or restyling any UI, or when it "looks off" |
| [`declutter`](declutter/) | Cleanup-only pre-PR pass — no bug fixes, no redesign | Before opening a PR; simplifying AI-written code |

### Ops & incidents

| Skill | One line | Reach for it when |
|---|---|---|
| [`incident`](incident/) | Production incident response — mitigate before diagnosing | Production down/degraded, alert firing, users impacted |
| [`postmortem`](postmortem/) | Blameless retrospective — plural causes, owned action items | After any incident, outage, data loss, or near-miss |
| [`release`](release/) | Staged-exposure deploys — verify, ramp, watch, rollback-ready | Deploying, releasing, publishing, flipping major flags |

### Codebase navigation

| Skill | One line | Reach for it when |
|---|---|---|
| [`onboard`](onboard/) | Fast accurate codebase orientation, one real flow end-to-end | Joining a project or picking up an unfamiliar repo |
| [`estimate`](estimate/) | Calibrated range estimates with stated uncertainty | Scoping work, negotiating a deadline |
| [`pr-workflow`](pr-workflow/) | Branch-to-merge hygiene — one concern, commits that tell the story | Creating commits/PRs, responding to review |

### Non-engineering

| Skill | One line | Reach for it when |
|---|---|---|
| [`data-analysis`](data-analysis/) | Analysis that survives scrutiny — interrogate before computing | Exploring datasets, answering questions with data, evaluating experiments |
| [`brainstorm`](brainstorm/) | Structured ideation — generate wide, converge with criteria | Brainstorming, generating options/names, un-sticking a plan |
| [`explain`](explain/) | Learner-targeted explanations — anchor, concrete before abstract | Teaching concepts, writing tutorials/onboarding docs |
| [`prompt-eng`](prompt-eng/) | Prompts engineered like software — spec, examples, eval set | Writing/debugging prompts, system prompts, LLM features |
| [`research-codebase`](research-codebase/) | Documentarian codebase mapping with file:line evidence | "How does X work / where does Y live" — before planning changes |

## How they compose

`lean-max-effort` is the backbone; the others deepen one of its phases: **Capture** → `spec` · **Plan** → `architect`, `breakdown` · **Execute** → `debug`, `refactor`, `testgen`, `declutter`, `migrate`, `api-design`, `frontend-design` · **Verify** → `prove`, `deep-review`, `sec-audit`, `perf`, `ci-triage` · **Continuity** → `handoff`, `onboard`, `pr-workflow`, `estimate`, `apply-working-process` · **Non-engineering** → `research`, `research-codebase`, `write`, `data-analysis`, `brainstorm`, `explain`, `prompt-eng` · **Ops** → `incident`, `postmortem`, `release`. Skills cross-reference each other by name (`debug` ends in `prove`; `breakdown` cards carry `spec`-style criteria; `incident` leads to `postmortem`).

## Install

```bash
# global (all projects):
cp -r <these directories> ~/.claude/skills/

# or project-scoped, versioned with the repo:
cp -r <these directories> <repo>/.claude/skills/
```

Or use [`../install.sh`](../install.sh). If `~/.claude/skills/` didn't exist before the current session, restart Claude Code once. Pair with a CLAUDE.md from [`../claude-md/`](../claude-md/) — skills fire per-task; CLAUDE.md rules are always on.

## Closing sections

A skill's closing section is `## Rules` for binding constraints, `## Anti-patterns` for failure modes to avoid, or both — no other spelling. Skills whose output is a deliverable (incident, postmortem, prove, research, spec, refactor, release, migrate, perf, sec-audit) also carry a `## Report` section with a short fenced skeleton. `scripts/check-skill-sections.py` enforces both, plus a duplicate-paragraph check across skills/.

## Naming notes

`deep-review`, `prove`, and `iterate` (local pack) dodge Claude Code's built-in `/review`, `/verify`, and `/loop` commands. `sec-audit` dodges `/security-review`; `declutter` dodges `/simplify`. If your Claude Code version has no conflict and you prefer the short names, rename the directory and the frontmatter `name:` together.
