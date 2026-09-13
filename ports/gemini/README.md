# ports/gemini — Gemini CLI

The free tier retired 2026-06-18, for the Antigravity CLI. The paid-tier Gemini CLI reads Agent Skills natively from `~/.gemini/skills/`: run `./install.sh --skills ~/.gemini/skills`.

To make `GEMINI.md` read `AGENTS.md` instead of a separate file, set `{"context": {"fileName": "AGENTS.md"}}` in Gemini CLI's `settings.json`, then keep one `AGENTS.md` at the repo root for every tool.
