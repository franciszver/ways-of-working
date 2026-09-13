#!/usr/bin/env python3
"""merge-hooks.py — merge hooks/settings-snippet.json into an existing
Claude Code settings.json without discarding what's already there.

Usage: merge-hooks.py TARGET_SETTINGS_JSON SNIPPET_JSON

Merges snippet["hooks"][event] entries into target["hooks"][event],
appending only entries not already present (safe to re-run).
"""
import json
import sys


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: merge-hooks.py TARGET_SETTINGS_JSON SNIPPET_JSON", file=sys.stderr)
        return 2
    target_path, snippet_path = sys.argv[1], sys.argv[2]

    with open(target_path) as f:
        target = json.load(f)
    with open(snippet_path) as f:
        snippet = json.load(f)

    target.setdefault("hooks", {})
    added = 0
    for event, entries in snippet.get("hooks", {}).items():
        existing = target["hooks"].setdefault(event, [])
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
