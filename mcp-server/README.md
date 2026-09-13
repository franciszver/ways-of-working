# mcp-server/ — the library as an MCP server

Exposes the skills and playbooks to **any MCP-capable agent** (Claude Code, Claude Desktop, Cursor, Gemini CLI, custom agents) over stdio.

| Surface | What |
|---|---|
| tool `list_skills()` | Catalog: name, profile, one-liner |
| tool `get_skill(name, profile)` | Full skill text — canonical (frontier) or local profile |
| tool `get_playbook(name)` | `routing` or `handoff` |
| tool `route(task_description)` | Keyword first-pass hints + the full ROUTING playbook to apply |
| prompts (one per canonical skill) | `/debug`, `/prove`, `/spec`, … inject the skill text + your task |

## Status: smoke-tested 2026-09-13

Verified end-to-end over real stdio transport (mcp SDK, `mcp<2`): tool registration (`list_skills`, `get_skill`, `get_playbook`, `route`), all 34 canonical prompts, canonical + local profiles, unknown-name error paths, `route()` keyword hints (including the pull-request/incident/CI-triage edge cases), and prompt injection with a task argument. Not yet exercised: long-running use inside a real agent session.

`mcp-server/test_server.py` covers the pure logic (frontmatter parsing, skill discovery, `route()` matching) without needing the `mcp` package — run it with `python3 -m pytest mcp-server -q`.

To re-verify the full server after changes, the interactive route is:

```bash
uv run --with "mcp[cli]" --directory /path/to/ways-of-working/mcp-server mcp dev server.py   # opens the MCP inspector
# call list_skills → expect the catalog of all 34 canonical + local skills;
# get_skill("debug") → full skill text; route() → keyword hints;
# prompts tab → all 34 canonical skills, each injecting its skill text plus a task.
```

Requires `uv` (or any Python ≥3.10 with the `mcp` package) — the machine this library was authored on shipped only Python 3.9, so check yours before registering.

Pinned to `mcp` 1.x: 2.x renamed `FastMCP` and removed `mcp.server.fastmcp`. Port tracked as a separate issue.

## Register

```bash
# Claude Code:
claude mcp add ways-of-working -- uv run --with "mcp[cli]" --directory /path/to/ways-of-working/mcp-server server.py

# Generic mcpServers JSON (Claude Desktop, Cursor, etc.):
{
  "mcpServers": {
    "ways-of-working": {
      "command": "uv",
      "args": ["run", "--with", "mcp[cli]", "--directory", "/path/to/ways-of-working/mcp-server", "server.py"]
    }
  }
}
```

The server runs over stdio by default. For a shared deployment reachable over HTTP instead of one process per client, change the `mcp.run()` call at the bottom of `server.py` to `mcp.run(transport="streamable-http")`.

**Upgrading from an earlier name:** if this server was registered under its previous name, remove that registration first (`claude mcp list` shows it), and re-export the library-root env var under its new name `WAYS_OF_WORKING_LIBRARY`.

The server locates the library relative to its own path; set `WAYS_OF_WORKING_LIBRARY=/path/to/ways-of-working` to point elsewhere (e.g. a copied deployment).

## Design notes

- **Prompts are the primary surface** — an MCP prompt injects the protocol into the calling agent's context, which is exactly what a skill is. The tools exist for agents that want to browse or self-select.
- `route()` is honest about being a heuristic: deterministic keyword hints, then the playbook for the calling model to apply. Judgment stays in ROUTING.md, not in regex.
- Frontmatter parsing is deliberately minimal (flat `key: value` between `---` fences) to keep the dependency surface at exactly `mcp`.
- `library.py` holds the pure logic (frontmatter parsing, skill discovery, `route()` matching) with no `mcp` import, so `test_server.py` runs without the `mcp` package installed. `server.py` is a thin MCP wrapper around it.
- When Claude Code is the client, prefer installing `skills/` natively (`../install.sh --claude-user`) — native skills auto-invoke; MCP prompts are user-invoked.
