# mcp-server/ — the library as an MCP server

Exposes the skills and playbooks to **any MCP-capable agent** (Claude Code, Claude Desktop, Cursor, Gemini CLI, custom agents) over stdio.

| Surface | What |
|---|---|
| tool `list_skills()` | Catalog: name, profile, one-liner |
| tool `get_skill(name, profile)` | Full skill text — canonical (frontier) or local profile |
| tool `get_playbook(name)` | `routing` or `handoff` |
| tool `route(task_description)` | Keyword first-pass hints + the full ROUTING playbook to apply |
| prompts (one per canonical skill) | `/debug`, `/prove`, `/spec`, … inject the skill text + your task |

## Status: smoke-tested 2026-07-06

Verified end-to-end over real stdio transport (mcp SDK on Python 3.12, 11/11 checks): tool registration, all 12 canonical prompts, canonical + local profiles, unknown-name error paths, `route()` hints, and prompt injection with a task argument. Not yet exercised: long-running use inside a real agent session.

To re-verify after changes, the interactive route is:

```bash
cd mcp-server
uv run --with "mcp[cli]" mcp dev server.py   # opens the MCP inspector
# call list_skills → expect the catalog; get_skill("debug") → full skill text;
# prompts tab → the 12 canonical skills.
```

Requires `uv` (or any Python ≥3.10 with the `mcp` package) — the machine this library was authored on shipped only Python 3.9, so check yours before registering.

## Register

```bash
# Claude Code:
claude mcp add fable-quality -- uv run --directory /path/to/fable-quality-library/mcp-server server.py

# Generic mcpServers JSON (Claude Desktop, Cursor, etc.):
{
  "mcpServers": {
    "fable-quality": {
      "command": "uv",
      "args": ["run", "--directory", "/path/to/fable-quality-library/mcp-server", "server.py"]
    }
  }
}
```

The server locates the library relative to its own path; set `FABLE_QUALITY_LIBRARY=/path/to/fable-quality-library` to point elsewhere (e.g. a copied deployment).

## Design notes

- **Prompts are the primary surface** — an MCP prompt injects the protocol into the calling agent's context, which is exactly what a skill is. The tools exist for agents that want to browse or self-select.
- `route()` is honest about being a heuristic: deterministic keyword hints, then the playbook for the calling model to apply. Judgment stays in ROUTING.md, not in regex.
- Frontmatter parsing is deliberately minimal (flat `key: value` between `---` fences) to keep the dependency surface at exactly `mcp`.
- When Claude Code is the client, prefer installing `skills/` natively (`../install.sh --claude-user`) — native skills auto-invoke; MCP prompts are user-invoked.
