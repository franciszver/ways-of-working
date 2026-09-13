---
description: Gets a red build green for the right reason — reads the first real failure, classifies it (code, test, flake, infra, drift), reproduces locally, fixes or quarantines with a ticket, never retries-until-green as a fix. Use when CI fails, a pipeline breaks, a build goes red, or a test is flaky. A local failure goes to `debug`.
---

Load and follow the skill at `.agents/skills/ci-triage/SKILL.md` (or `.agent/skills/ci-triage/SKILL.md`). Apply it to the argument given with the command.
