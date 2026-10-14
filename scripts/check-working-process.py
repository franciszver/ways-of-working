#!/usr/bin/env python3
"""check-working-process.py: the working-process rules must agree on every surface.

Checks, all grep-style:
  1. No surface names WORKPLAN.md or DECISIONS.md.
  2. No surface says "three gates" (the process has four).
     skills/local-llm-loop is skipped: its driver runs three stages by design.
  3. The canonical skill and its local twin name CURR-AGENT-EFFORT,
     clean-code, ste-writing, plain-language, and "Four gates".
CHANGELOG.md and PLAN.md at the repo root keep history and are skipped.
Exits 1 on any failure.
"""
import re
import sys
from pathlib import Path

SKIP_PATHS = {"CHANGELOG.md", "PLAN.md", "scripts/check-working-process.py"}
SKIP_DIRS = {".git", "node_modules", "__pycache__", ".pytest_cache"}
LOOP_DIRS = ("skills/local-llm-loop/", "build/claude-code/skills/local-llm-loop/")
ALWAYS_BANNED = [
    (re.compile(r"WORKPLAN\.md"), "names WORKPLAN.md"),
    (re.compile(r"DECISIONS\.md"), "names DECISIONS.md"),
]
GATE_COUNT_BANNED = (re.compile(r"\b(three|3)[- ]gates?\b", re.IGNORECASE), 'says "three gates"')
REQUIRED = ["CURR-AGENT-EFFORT", "clean-code", "ste-writing", "plain-language", "Four gates"]
SKILLS = ["skills/apply-working-process/SKILL.md", "skills-local/apply-working-process/SKILL.md"]


def surfaces(root: Path):
    for path in sorted(root.rglob("*")):
        rel = path.relative_to(root)
        if not path.is_file() or rel.as_posix() in SKIP_PATHS or SKIP_DIRS & set(rel.parts):
            continue
        try:
            yield rel.as_posix(), path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue


def banned_failures(root: Path) -> list:
    failures = []
    for rel, text in surfaces(root):
        rules = list(ALWAYS_BANNED)
        if not rel.startswith(LOOP_DIRS):
            rules.append(GATE_COUNT_BANNED)
        for number, line in enumerate(text.splitlines(), 1):
            failures += [f"{rel}:{number}: {label}" for pattern, label in rules if pattern.search(line)]
    return failures


def required_failures(root: Path) -> list:
    failures = []
    for rel in SKILLS:
        path = root / rel
        if not path.is_file():
            failures.append(f"{rel}: missing")
            continue
        text = path.read_text(encoding="utf-8")
        failures += [f"{rel}: lacks {term}" for term in REQUIRED if term not in text]
    return failures


def main() -> int:
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.cwd()
    failures = banned_failures(root) + required_failures(root)
    for failure in failures:
        print("FAIL:", failure)
    if failures:
        return 1
    print("working-process: four gates, effort plan, no decision log, on every surface.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
