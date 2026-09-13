# hooks/ — Claude Code automation

Four hooks that enforce mechanically what the skills teach behaviorally. Skills persuade; hooks guarantee.

| Hook | Event | Does | Blocks? |
|---|---|---|---|
| `guardrails.sh` | PreToolUse (Bash) | Blocks catastrophic commands: `rm -rf /` or `~`, force-push to main/master, raw disk writes/mkfs, `chmod -R 777 /`, fork bombs | Yes — JSON `permissionDecision: deny` on stdout, exit 2 with the reason on stderr as fallback |
| `test-gate.sh` | PreToolUse (Bash) | On `git commit`, runs your test command first; failing tests block the commit. **Opt-in**: only active if `.claude/test-command` exists | Yes, when tests fail — same JSON-plus-exit-2 form as `guardrails.sh` |
| `format-on-stop.sh` | Stop, SubagentStop | Formats changed files with the project's configured formatter (prettier / ruff / black / gofmt / cargo fmt) | Never — always exits 0 |
| `failure-counter.sh` | PostToolUseFailure (Bash) | **Opt-in per project** (`install.sh --hooks`, not shipped by the plugin): appends every failed command to `.claude/failure-log`; once the same command fails twice in a row, adds an `additionalContext`/`systemMessage` reminder ("same fix failing twice means the hypothesis is wrong") | Never — always exits 0, never a permission decision |

`guardrails.sh` registers on `PreToolUse` only. `PermissionRequest` was
considered and rejected: per the hooks docs, `PreToolUse` already runs
before every tool call, `PermissionRequest`'s decision shape differs from
the `PreToolUse`/`PostToolUseFailure` decision shape this file relies on,
and exit 2 is not honored on `PermissionRequest` — registering there would
add a second, differently-behaved path for no coverage gain.

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

`failure-counter.sh` uses a different shape, since `PostToolUseFailure` does
not accept a `permissionDecision` (it isn't gating anything — the tool call
already failed):

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUseFailure",
    "additionalContext": "<why>"
  },
  "systemMessage": "<why>"
}
```

All three scripts share the input-parsing and JSON-emitting code in
`hooks/scripts/_hook_lib.sh` (`read_hook_input`, `emit_decision`) — source
it, don't execute it.

`plugin-hooks.json` is generated from `settings-snippet.json` — run `scripts/merge-hooks.py --emit-plugin > hooks/plugin-hooks.json` after editing the snippet, never hand-edit it.

`.claude/test-command` is executed as a shell command by `test-gate.sh` — treat it as code, not config. `.claude/failure-log` is written by `failure-counter.sh`; add it to your project's `.gitignore` (this repo's own `.gitignore` does).

The plugin ships `guardrails.sh` (and the `_hook_lib.sh` it sources) only. `test-gate.sh`, `format-on-stop.sh`, and `failure-counter.sh` stay per-project opt-in via `install.sh --hooks`, never installed by the plugin: `format-on-stop.sh` runs `npx --no-install`, which resolves the *project's* `node_modules/.bin`, so a plugin-installed copy would let a cloned repo run code via the Stop/SubagentStop hook; `test-gate.sh` runs the repo-controlled `.claude/test-command` file as a shell command, which a plugin install has no opt-in gate for; `failure-counter.sh` writes repo-resident content (`.claude/failure-log`) on every failed command in every project the plugin is active in, which likewise needs the explicit per-project opt-in.

## Install (per project)

```bash
mkdir -p <repo>/.claude/hooks
cp scripts/*.sh <repo>/.claude/hooks/
chmod +x <repo>/.claude/hooks/*.sh

# merge settings-snippet.json into <repo>/.claude/settings.json
# (create the file with exactly this content if it doesn't exist)

# opt-in — enable the test gate:
echo "npm test" > <repo>/.claude/test-command

# opt-in — gitignore the failure counter's log:
echo ".claude/failure-log" >> <repo>/.gitignore
```

Then restart the Claude Code session (hooks config is captured at startup) and run `/hooks` to confirm they're registered.

**Last verified: 2026-09-13.** Smoke-tested with stub JSON piped on stdin, from the repo root:

```bash
echo '{"tool_input":{"command":"rm -rf /"}}' | hooks/scripts/guardrails.sh; echo "exit=$?"
echo '{"tool_input":{"command":"ls"}}' | hooks/scripts/guardrails.sh; echo "exit=$?"
CLAUDE_PROJECT_DIR="$PWD" hooks/scripts/format-on-stop.sh; echo "exit=$?"
```

Results:

```
$ echo '{"tool_input":{"command":"rm -rf /"}}' | hooks/scripts/guardrails.sh; echo "exit=$?"
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "BLOCKED by guardrails hook: recursive delete of / or the home directory. If this is genuinely intended, the user must run it themselves in a terminal."}}
BLOCKED by guardrails hook: recursive delete of / or the home directory. If this is genuinely intended, the user must run it themselves in a terminal.
exit=2

$ echo '{"tool_input":{"command":"ls"}}' | hooks/scripts/guardrails.sh; echo "exit=$?"
exit=0

$ CLAUDE_PROJECT_DIR="$PWD" hooks/scripts/format-on-stop.sh; echo "exit=$?"
exit=0
```

Also re-verified: `test-gate.sh` blocks on a failing `.claude/test-command`
(JSON `deny` plus exit 2) and allows on a passing one (exit 0); a
`.claude/test-command` of `false | cat` also blocks, proving `-o pipefail`
scoped to the `bash -c` subshell catches the real failure through the pipe
instead of `cat`'s exit code. `failure-counter.sh` stays silent on the
first failure and emits the `additionalContext`/`systemMessage` reminder on
the second consecutive identical failure — confirmed keyed by a sha1 hash
of the full command, logging `timestamp<TAB>hash<TAB>first-line-only`, and
refusing to write when `.claude/failure-log` is a symlink. To confirm the
install landed correctly in *your* project:

1. `echo '{"tool_input":{"command":"rm -rf /"}}' | .claude/hooks/guardrails.sh; echo "exit=$?"` → expect the BLOCKED JSON/message and `exit=2`.
2. `echo '{"tool_input":{"command":"ls"}}' | .claude/hooks/guardrails.sh; echo "exit=$?"` → expect silence and `exit=0`.
3. With `.claude/test-command` present and a deliberately failing test, ask Claude to commit → expect the block with test output.

## Design decisions

- **Fail-open everywhere.** A hook that can't parse its input allows the action rather than bricking the session. The guardrail is a seatbelt, not the only protection — Claude Code's own permission system remains the primary gate.
- **Guardrails block only high-confidence catastrophes.** An aggressive deny-list trains users to disable the hook. Add project-specific patterns to `guardrails.sh` where the blast radius justifies the friction.
- **Test gate is opt-in via a file** (`.claude/test-command`, first line = the command) so cloning this config into a repo never surprises anyone. Its hook timeout is set to 300s in the snippet — raise it if your suite is slower, or point the gate at a fast subset (`npm test -- --changed`). The command runs as `bash -o pipefail -c "$TEST_CMD"` — `-o pipefail` is passed to that `bash -c` invocation itself, since `set -o pipefail` in the hook script's own shell does not cross into a separate `bash -c` process — so a piped test command (`npm test | tee log`) fails the gate on the real test failure, not on `tee`'s exit code.
- **Formatter never blocks and never installs anything** (`npx --no-install`); it only runs formatters the project already configures. It also runs on `SubagentStop`, so subagent-only sessions get the same formatting pass as the main session.
- **Failure counter is advisory, never blocking, and opt-in per project.** It reports via `additionalContext`/`systemMessage`, never a permission decision, so a slow or flaky command is never turned into a hard stop — only a nudge to reconsider the approach. It writes to the project's own `.claude/failure-log`, which is why it stays out of the plugin (see above) and belongs in the project's `.gitignore`.

## Requirements

`bash`, `git`, `python3` (for JSON parsing in the PreToolUse/PostToolUseFailure hooks, via `_hook_lib.sh`; they no-op without it), plus whatever formatters/test runners the project already uses.
