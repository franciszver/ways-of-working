#!/usr/bin/env python3
"""check-working-process.py: the working-process rules must agree on every surface.

Checks, all grep-style:
  1. No surface names WORKPLAN.md or DECISIONS.md.
  2. No surface says "three gates" (the process has four).
     skills/local-llm-loop is skipped: its driver runs three stages by design.
  3. The canonical skill and its local twin name CURR-AGENT-EFFORT,
     clean-code, ste-writing, and plain-language.
CHANGELOG.md and PLAN.md keep history and are skipped. Exits 1 on any failure.
"""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import _lib  # noqa: F401  (shared helpers; keeps the check-script layout)

SKIP_FILES = {"CHANGELOG.md", "PLAN.md", "check-working-process.py"}
SKIP_DIRS = {".git", "node_modules", "__pycache__", ".pytest_cache"}
GATES_SKIP = ("skills/local-llm-loop/", "build/claude-code/skills/local-llm-loop/")
BANNED = [
    (re.compile(r"WORKPLAN\.md"), "names WORKPLAN.md", False),
    (re.compile(r"DECISIONS\.md"), "names DECISIONS.md", False),
    (re.compile(r"three gates", re.IGNORECASE), 'says "three gates"', True),
]
REQUIRED = ["CURR-AGENT-EFFORT", "clean-code", "ste-writing", "plain-language"]
SKILLS = ["skills/apply-working-process/SKILL.md", "skills-local/apply-working-process/SKILL.md"]


def surfaces(root: Path):
    for p in sorted(root.rglob("*")):
        if not p.is_file() or p.name in SKIP_FILES:
            continue
        if SKIP_DIRS & set(p.relative_to(root).parts):
            continue
        yield p


def main() -> int:
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.cwd()
    failures = []

    for p in surfaces(root):
        rel = p.relative_to(root).as_posix()
        try:
            text = p.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        for n, line in enumerate(text.splitlines(), 1):
            for pat, label, gates_rule in BANNED:
                if gates_rule and rel.startswith(GATES_SKIP):
                    continue
                if pat.search(line):
                    failures.append(f"{rel}:{n}: {label}")

    for rel in SKILLS:
        path = root / rel
        if not path.is_file():
            failures.append(f"{rel}: missing")
            continue
        text = path.read_text(encoding="utf-8")
        for term in REQUIRED:
            if term not in text:
                failures.append(f"{rel}: lacks {term}")

    for f in failures:
        print("FAIL:", f)
    if failures:
        return 1
    print("working-process: four gates, effort plan, no decision log, on every surface.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
