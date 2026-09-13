#!/usr/bin/env python3
"""merge-hooks.py — merge hooks/settings-snippet.json into an existing
Claude Code settings.json without discarding what's already there.

Usage: merge-hooks.py TARGET_SETTINGS_JSON SNIPPET_JSON
       merge-hooks.py --emit-plugin

--emit-plugin reads hooks/settings-snippet.json, rewrites its project-path
hook commands to plugin-root paths, drops test-gate.sh and format-on-stop.sh
(the plugin ships only guardrails.sh — the other two stay per-project
opt-in via install.sh --hooks; see hooks/README.md), and prints the result
as JSON — this is how hooks/plugin-hooks.json is generated. It is never
hand-edited.

Merges snippet["hooks"][event] entries into target["hooks"][event], keyed by
matcher and then by each hook's `command` string: a command already present
is updated in place (e.g. a changed timeout), never duplicated; a new
command is appended. Never writes the target file unless both inputs parse
and merge cleanly, so a failure never corrupts an existing settings.json.
The write itself is atomic (temp file in the target's directory, then
os.replace).
"""
import json
import os
import sys
import tempfile
from pathlib import Path

PROJECT_HOOK_PREFIX = '"$CLAUDE_PROJECT_DIR"/.claude/hooks/'
PLUGIN_HOOK_PREFIX = '"${CLAUDE_PLUGIN_ROOT}"/hooks/scripts/'

# Excluded from the plugin manifest: plugin hooks fire in every project the
# user opens, with no per-project opt-in.
# - test-gate.sh runs the first line of the repo-controlled file
#   .claude/test-command as a shell command on every commit-matching Bash
#   call.
# - format-on-stop.sh runs `npx --no-install prettier` (and equivalents),
#   which resolves the *project's* node_modules/.bin — a cloned repo can
#   ship code there and have the plugin's Stop hook execute it.
# - failure-counter.sh writes repo-resident content (.claude/failure-log)
#   on every failed command in every project the plugin is active in.
# All three stay safe only because install.sh --hooks is an explicit,
# per-project opt-in. Never add any of them back to the plugin.
PLUGIN_EXCLUDED_SCRIPTS = ("test-gate.sh", "format-on-stop.sh", "failure-counter.sh")


def fail(message: str) -> int:
    print(f"FAIL: {message}", file=sys.stderr)
    return 1


def merge_entries(existing_entries: list, new_entries: list) -> tuple:
    """Merge new_entries into existing_entries in place, keyed by matcher
    then by each hook's `command`. Returns (added, updated) counts."""
    added = 0
    updated = 0
    for new_entry in new_entries:
        matcher = new_entry.get("matcher")
        target_entry = None
        for existing_entry in existing_entries:
            if existing_entry.get("matcher") == matcher:
                target_entry = existing_entry
                break
        if target_entry is None:
            target_entry = {k: v for k, v in new_entry.items() if k != "hooks"}
            target_entry["hooks"] = []
            existing_entries.append(target_entry)

        existing_hooks = target_entry.setdefault("hooks", [])
        for new_hook in new_entry.get("hooks", []):
            command = new_hook.get("command")
            replaced = False
            for i, hook in enumerate(existing_hooks):
                if hook.get("command") == command:
                    if hook != new_hook:
                        existing_hooks[i] = new_hook
                        updated += 1
                    replaced = True
                    break
            if not replaced:
                existing_hooks.append(new_hook)
                added += 1
    return added, updated


def emit_plugin() -> int:
    snippet_path = Path(__file__).resolve().parent.parent / "hooks" / "settings-snippet.json"
    try:
        snippet = json.loads(snippet_path.read_text())
    except (FileNotFoundError, json.JSONDecodeError) as e:
        return fail(f"{snippet_path} is not readable/valid JSON ({e})")

    plugin_hooks = {}
    for event, entries in snippet.get("hooks", {}).items():
        kept_entries = []
        for entry in entries:
            kept_hooks = []
            for hook in entry.get("hooks", []):
                command = hook.get("command", "")
                if any(script in command for script in PLUGIN_EXCLUDED_SCRIPTS):
                    continue
                if isinstance(command, str) and PROJECT_HOOK_PREFIX in command:
                    hook["command"] = command.replace(PROJECT_HOOK_PREFIX, PLUGIN_HOOK_PREFIX)
                kept_hooks.append(hook)
            if not kept_hooks:
                continue
            entry = dict(entry, hooks=kept_hooks)
            kept_entries.append(entry)
        if kept_entries:
            plugin_hooks[event] = kept_entries

    print(json.dumps({"hooks": plugin_hooks}, indent=2))
    return 0


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "--emit-plugin":
        return emit_plugin()
    if len(sys.argv) != 3:
        print("usage: merge-hooks.py TARGET_SETTINGS_JSON SNIPPET_JSON", file=sys.stderr)
        print("       merge-hooks.py --emit-plugin", file=sys.stderr)
        return 2
    target_path, snippet_path = sys.argv[1], sys.argv[2]

    try:
        with open(target_path) as f:
            target = json.load(f)
    except FileNotFoundError:
        return fail(f"{target_path} does not exist")
    except json.JSONDecodeError as e:
        return fail(f"{target_path} is not valid JSON ({e}); fix it by hand, then re-run")

    try:
        with open(snippet_path) as f:
            snippet = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError) as e:
        return fail(f"{snippet_path} is not readable/valid JSON ({e})")

    if not isinstance(target, dict):
        return fail(f"{target_path} top level is not a JSON object")

    existing_hooks = target.get("hooks", {})
    if existing_hooks is None:
        existing_hooks = {}
    if not isinstance(existing_hooks, dict):
        return fail(f"{target_path}'s \"hooks\" key is not an object; merge it by hand")
    target["hooks"] = existing_hooks

    snippet_hooks = snippet.get("hooks", {}) or {}
    if not isinstance(snippet_hooks, dict):
        return fail(f"{snippet_path}'s \"hooks\" key is not an object")

    total_added = 0
    total_updated = 0
    for event, entries in snippet_hooks.items():
        if not isinstance(entries, list):
            return fail(f"{snippet_path}: hooks.{event} is not a list")
        existing = existing_hooks.get(event)
        if existing is None:
            existing = []
        if not isinstance(existing, list):
            return fail(f"{target_path}: hooks.{event} is not a list; merge it by hand")
        existing_hooks[event] = existing
        added, updated = merge_entries(existing, entries)
        total_added += added
        total_updated += updated

    target_dir = os.path.dirname(os.path.abspath(target_path)) or "."
    fd, tmp_path = tempfile.mkstemp(dir=target_dir, prefix=".merge-hooks-", suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(target, f, indent=2)
            f.write("\n")
        os.replace(tmp_path, target_path)
    except BaseException:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise

    print(
        f"Merged {total_added} new hook command(s), updated {total_updated} "
        f"existing into {target_path}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
