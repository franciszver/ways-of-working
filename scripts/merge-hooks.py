#!/usr/bin/env python3
"""merge-hooks.py — merge hooks/settings-snippet.json into an existing
Claude Code settings.json without discarding what's already there.

Usage: merge-hooks.py TARGET_SETTINGS_JSON SNIPPET_JSON
       merge-hooks.py --emit-plugin

--emit-plugin reads hooks/settings-snippet.json, rewrites its project-path
hook commands to plugin-root paths, and prints the result as JSON — this is
how hooks/plugin-hooks.json is generated. It is never hand-edited.

Merges snippet["hooks"][event] entries into target["hooks"][event],
appending only entries not already present (safe to re-run). Never
writes the target file unless both inputs parse and merge cleanly, so
a failure never corrupts an existing settings.json.
"""
import json
import sys
from pathlib import Path

PROJECT_HOOK_PREFIX = '"$CLAUDE_PROJECT_DIR"/.claude/hooks/'
PLUGIN_HOOK_PREFIX = '"${CLAUDE_PLUGIN_ROOT}"/hooks/scripts/'


def fail(message: str) -> int:
    print(f"FAIL: {message}", file=sys.stderr)
    return 1


def emit_plugin() -> int:
    snippet_path = Path(__file__).resolve().parent.parent / "hooks" / "settings-snippet.json"
    try:
        snippet = json.loads(snippet_path.read_text())
    except (FileNotFoundError, json.JSONDecodeError) as e:
        return fail(f"{snippet_path} is not readable/valid JSON ({e})")

    for entries in snippet.get("hooks", {}).values():
        for entry in entries:
            for hook in entry.get("hooks", []):
                command = hook.get("command")
                if isinstance(command, str) and PROJECT_HOOK_PREFIX in command:
                    hook["command"] = command.replace(PROJECT_HOOK_PREFIX, PLUGIN_HOOK_PREFIX)

    print(json.dumps(snippet, indent=2))
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

    added = 0
    for event, entries in snippet_hooks.items():
        if not isinstance(entries, list):
            return fail(f"{snippet_path}: hooks.{event} is not a list")
        existing = existing_hooks.get(event)
        if existing is None:
            existing = []
        if not isinstance(existing, list):
            return fail(f"{target_path}: hooks.{event} is not a list; merge it by hand")
        existing_hooks[event] = existing
        for entry in entries:
            if entry not in existing:
                existing.append(entry)
                added += 1

    with open(target_path, "w") as f:
        json.dump(target, f, indent=2)
        f.write("\n")

    print(f"Merged {added} new hook entr{'y' if added == 1 else 'ies'} into {target_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
