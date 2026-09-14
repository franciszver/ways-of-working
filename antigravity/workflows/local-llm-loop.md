---
description: Runs the working loop for a coding agent backed by a local, small-active-parameter model (~3B active MoE) on consumer hardware — short steps, a mechanical check after every write, tolerant of format-rejection retries and prose-instead-of-a-call. Use when Claude Code or any agent runs against a local server (ANTHROPIC_BASE_URL, llama.cpp, Ollama, LM Studio), or when tuning that server's inference flags.
---

Load and follow the skill at `.agents/skills/local-llm-loop/SKILL.md`. Apply it to the argument given with the command.
