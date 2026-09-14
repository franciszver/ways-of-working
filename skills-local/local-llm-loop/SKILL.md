---
name: local-llm-loop
description: "Runs the working loop for a coding agent backed by a local, small-active-parameter model (~3B active MoE) on consumer hardware — short steps, a mechanical check after every write, tolerant of format-rejection retries and prose-instead-of-a-call. Use when Claude Code or any agent runs against a local server (ANTHROPIC_BASE_URL, llama.cpp, Ollama, LM Studio), or when tuning that server's inference flags."
---

<!-- local: derived-from: skills/local-llm-loop/SKILL.md@c9c625ff116b -->

# Local LLM Loop

You are a local model. Work in small, checked steps — this is a measured constraint on your own reliability, not a style preference.

## Rules

1. Break the task into steps stated in under ~500-700 output tokens each, one file (or one focused change) per turn. Never generate a whole file/module/service in one call.
2. After every write: parse it, load it, check for errors — before starting the next step. Never queue write N+1 before write N's check has actually returned.
3. Keep every tool call small — target under ~700 tokens per call.
4. If a call is rejected as malformed (HTTP 500, a message about the expected format), that is not a crash: retry the same step once.
5. If the harness reports "Resource not found" (HTTP 404), stop — the endpoint is misconfigured, not you. Do not keep retrying.
6. A prose answer or a clarifying question is a normal outcome, not a failure — `tool_choice: required` is not guaranteed to force a structured call on this stack. If you're unsure a tool call is needed, ask in prose rather than emitting a malformed call.
7. When recovering from a missing file or wrong path, keep exploring toward the right name (list the directory, check nearby paths) rather than giving up after one failed lookup.
8. Before you stop, write the state file in the `handoff` skill's format so a fresh session with no memory of this one can resume from it alone.

## Anti-patterns

- One-shot generation of a whole file/module/service in a single call.
- Chaining a second write ahead of the first write's mechanical check.
- Treating a prose reply or a clarifying question as an error to route around.
- Stopping after one failed lookup instead of exploring toward the right path.
