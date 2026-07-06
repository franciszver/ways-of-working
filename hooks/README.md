# hooks/ — Claude Code automation

Three hooks that enforce mechanically what the skills teach behaviorally. Skills persuade; hooks guarantee.

| Hook | Event | Does | Blocks? |
|---|---|---|---|
| `guardrails.sh` | PreToolUse (Bash) | Blocks catastrophic commands: `rm -rf /` or `~`, force-push to main/master, raw disk writes/mkfs, `chmod -R 777 /`, fork bombs | Yes — exit 2 with the reason |
| `test-gate.sh` | PreToolUse (Bash) | On `git commit`, runs your test command first; failing tests block the commit. **Opt-in**: only active if `.claude/test-command` exists | Yes, when tests fail |
| `format-on-stop.sh` | Stop | Formats changed files with the project's configured formatter (prettier / ruff / black / gofmt / cargo fmt) | Never — always exits 0 |

## Install (per project)

```bash
mkdir -p <repo>/.claude/hooks
cp scripts/*.sh <repo>/.claude/hooks/
chmod +x <repo>/.claude/hooks/*.sh

# merge settings-snippet.json into <repo>/.claude/settings.json
# (create the file with exactly this content if it doesn't exist)

# optional — enable the test gate:
echo "npm test" > <repo>/.claude/test-command
```

Then restart the Claude Code session (hooks config is captured at startup) and run `/hooks` to confirm they're registered.

**These scripts ship untested by design** (authored, not executed). Before trusting them on a real project, spend two minutes verifying:

1. `echo '{"tool_input":{"command":"rm -rf /"}}' | .claude/hooks/guardrails.sh; echo "exit=$?"` → expect the BLOCKED message and `exit=2`.
2. `echo '{"tool_input":{"command":"ls"}}' | .claude/hooks/guardrails.sh; echo "exit=$?"` → expect silence and `exit=0`.
3. With `.claude/test-command` present and a deliberately failing test, ask Claude to commit → expect the block with test output.

## Design decisions

- **Fail-open everywhere.** A hook that can't parse its input allows the action rather than bricking the session. The guardrail is a seatbelt, not the only protection — Claude Code's own permission system remains the primary gate.
- **Guardrails block only high-confidence catastrophes.** An aggressive deny-list trains users to disable the hook. Add project-specific patterns to `guardrails.sh` where the blast radius justifies the friction.
- **Test gate is opt-in via a file** (`.claude/test-command`, first line = the command) so cloning this config into a repo never surprises anyone. Its hook timeout is set to 300s in the snippet — raise it if your suite is slower, or point the gate at a fast subset (`npm test -- --changed`).
- **Formatter never blocks and never installs anything** (`npx --no-install`); it only runs formatters the project already configures.

## Requirements

`bash`, `git`, `python3` (for JSON parsing in the two PreToolUse hooks; they no-op without it), plus whatever formatters/test runners the project already uses.
