# mcp-server/ — the library as an MCP server

Exposes the skills and playbooks to **any MCP-capable agent** (Claude Code, Claude Desktop, Cursor, Gemini CLI, custom agents) over stdio.

| Surface | What |
|---|---|
| tool `list_skills()` | Catalog: name, profile, one-liner |
| tool `get_skill(name, profile)` | Full skill text — canonical (frontier) or local profile |
| tool `get_playbook(name)` | `routing` or `handoff` |
| tool `route(task_description)` | Keyword first-pass hints + the full ROUTING playbook to apply |
| prompts (one per canonical skill) | `/debug`, `/prove`, `/spec`, … inject the skill text + your task |

## Status: authored, not executed

This server was written as plumbing (any model can finish/fix it using the library itself). Before first use, run the two-minute smoke test:

```bash
cd mcp-server
uv run --with "mcp[cli]" mcp dev server.py   # opens the MCP inspector
# in the inspector: call list_skills → expect the catalog;
# call get_skill("debug") → expect the full skill text;
# check the prompts tab lists the 12 canonical skills.
```

Likely first-run issues, should they occur: the `Prompt.from_function`/`add_prompt` calls track the `mcp` SDK's FastMCP API — if the SDK has drifted, `mcp dev` will name the missing symbol; adjust per current SDK docs.

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
