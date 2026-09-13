# hooks/ — Claude Code automation

Four hooks that enforce mechanically what the skills teach behaviorally. Skills persuade; hooks guarantee.

| Hook | Event | Does | Blocks? |
|---|---|---|---|
| `guardrails.sh` | PreToolUse (Bash), PermissionRequest (Bash) | Blocks catastrophic commands: `rm -rf /` or `~`, force-push to main/master, raw disk writes/mkfs, `chmod -R 777 /`, fork bombs | Yes — JSON `permissionDecision: deny` on stdout, exit 2 with the reason on stderr as fallback |
| `test-gate.sh` | PreToolUse (Bash) | On `git commit`, runs your test command first; failing tests block the commit. **Opt-in**: only active if `.claude/test-command` exists | Yes, when tests fail — same JSON-plus-exit-2 form as `guardrails.sh` |
| `format-on-stop.sh` | Stop, SubagentStop | Formats changed files with the project's configured formatter (prettier / ruff / black / gofmt / cargo fmt) | Never — always exits 0 |
| `failure-counter.sh` | PostToolUseFailure (Bash) | Appends every failed command to `.claude/failure-log`; once the same command fails twice in a row, adds a `systemMessage` reminder ("same fix failing twice means the hypothesis is wrong") | Never — always exits 0, never a permission decision |

Registering `guardrails.sh` on both PreToolUse and PermissionRequest is belt-and-braces: PermissionRequest also fires for tool calls that reach a permission decision without going through PreToolUse first, so relying on PreToolUse alone would miss those.

### The JSON decision form

`guardrails.sh` and `test-gate.sh` print this shape on stdout when they block, matching the hooks documentation's decision-output contract:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "<why>"
  }
}
```

Both scripts also still exit 2 with the reason on stderr, as a fallback for any client that only honors the exit code rather than parsing stdout.

`plugin-hooks.json` is generated from `settings-snippet.json` — run `scripts/merge-hooks.py --emit-plugin > hooks/plugin-hooks.json` after editing the snippet, never hand-edit it.

`.claude/test-command` is executed as a shell command by `test-gate.sh` — treat it as code, not config.

The plugin ships `guardrails.sh` and `failure-counter.sh`. `test-gate.sh` and `format-on-stop.sh` stay per-project opt-in via `install.sh --hooks`, never installed by the plugin — `format-on-stop.sh` runs `npx --no-install`, which resolves the *project's* `node_modules/.bin`, so a plugin-installed copy would let a cloned repo run code via the Stop/SubagentStop hook. `test-gate.sh` runs the repo-controlled `.claude/test-command` file as a shell command, which a plugin install has no opt-in gate for. `failure-counter.sh` is safe to ship in the plugin: it runs no repo-controlled content — it only reads the tool-call JSON Claude Code itself passes in and appends/reads its own log file.

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

**Last verified: 2026-09-13.** Smoke-tested with stub JSON piped on stdin, from the repo root:

```bash
echo '{"tool_input":{"command":"rm -rf /"}}' | hooks/scripts/guardrails.sh; echo "exit=$?"
echo '{"tool_input":{"command":"ls"}}' | hooks/scripts/guardrails.sh; echo "exit=$?"
CLAUDE_PROJECT_DIR="$PWD" hooks/scripts/format-on-stop.sh; echo "exit=$?"
```

Results: the first printed the `permissionDecision: deny` JSON plus the BLOCKED message on stderr and exited 2; the second printed nothing and exited 0; the third exited 0 (no-op — no formatter config in this repo's root). Also re-verified: `test-gate.sh` blocks on a failing `.claude/test-command` (JSON `deny` plus exit 2) and allows on a passing one (exit 0); `failure-counter.sh` logs a failure silently on the first occurrence and adds the `systemMessage` reminder on the second consecutive identical failure. To confirm the install landed correctly in *your* project:

1. `echo '{"tool_input":{"command":"rm -rf /"}}' | .claude/hooks/guardrails.sh; echo "exit=$?"` → expect the BLOCKED JSON/message and `exit=2`.
2. `echo '{"tool_input":{"command":"ls"}}' | .claude/hooks/guardrails.sh; echo "exit=$?"` → expect silence and `exit=0`.
3. With `.claude/test-command` present and a deliberately failing test, ask Claude to commit → expect the block with test output.

## Design decisions

- **Fail-open everywhere.** A hook that can't parse its input allows the action rather than bricking the session. The guardrail is a seatbelt, not the only protection — Claude Code's own permission system remains the primary gate.
- **Guardrails block only high-confidence catastrophes.** An aggressive deny-list trains users to disable the hook. Add project-specific patterns to `guardrails.sh` where the blast radius justifies the friction.
- **Test gate is opt-in via a file** (`.claude/test-command`, first line = the command) so cloning this config into a repo never surprises anyone. Its hook timeout is set to 300s in the snippet — raise it if your suite is slower, or point the gate at a fast subset (`npm test -- --changed`). The command runs inside a subshell with `set -o pipefail`, so a piped test command (`npm test | tee log`) fails the gate on the real test failure, not on `tee`'s exit code.
- **Formatter never blocks and never installs anything** (`npx --no-install`); it only runs formatters the project already configures. It also runs on `SubagentStop`, so subagent-only sessions get the same formatting pass as the main session.
- **Failure counter is advisory, never blocking.** It reports via `systemMessage`, not `permissionDecision`, so a slow or flaky command is never turned into a hard stop — only a nudge to reconsider the approach.

## Requirements

`bash`, `git`, `python3` (for JSON parsing in the PreToolUse/PermissionRequest/PostToolUseFailure hooks; they no-op without it), plus whatever formatters/test runners the project already uses.
