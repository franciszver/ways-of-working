#!/usr/bin/env python3
"""check-working-process.py: no stale working-process terms, and required terms present.

Usage: check-working-process.py [ROOT] [--owner-file PATH]

Checks:
  1. No tracked text file names the old plan file or the old decision log,
     or says "three gates". Files under build/ are skipped: build-profile.py
     --check covers that generated copy.
  2. The canonical skill and its local twin name CURR-AGENT-EFFORT,
     clean-code, ste-writing, plain-language, and "Four gates".
  3. With --owner-file PATH, the same checks run on that file when it
     exists. An absent file is skipped silently.

This is a grep, not proof that the rules are followed.

Allow rule: a rule skips the paths in its exempt list. CHANGELOG.md and
PLAN.md keep history. This script and its test hold the stale terms on
purpose. skills/local-llm-loop/ may say "three gates" because its driver
runs three stages. Any other line that must quote a stale term on purpose
carries the marker "check-working-process: allow" on the same line.
Exits 1 on any failure.
"""
import argparse
import re
import subprocess
import sys
from pathlib import Path

ALLOW_MARKER = "check-working-process: allow"
HISTORY = ("CHANGELOG.md", "PLAN.md", "scripts/check-working-process.py", "scripts/test-check-working-process.sh")
# (pattern, label, exempt path prefixes)
BANNED = [
    (re.compile(r"WORKPLAN\.md"), "names the old plan file", HISTORY),
    (re.compile(r"DECISIONS\.md"), "names the old decision log", HISTORY),
    (re.compile(r"\bthree[- ]gates\b", re.IGNORECASE), 'says "three gates"', HISTORY + ("skills/local-llm-loop/",)),
]
REQUIRED = ["CURR-AGENT-EFFORT", "clean-code", "ste-writing", "plain-language", "Four gates"]
SKILLS = ["skills/apply-working-process/SKILL.md", "skills-local/apply-working-process/SKILL.md"]
TEXT_SUFFIXES = {".md", ".mdc", ".py", ".sh", ".json", ".yaml", ".yml", ".txt", ".toml"}
SKIP_DIRS = {".git", "build", "node_modules", "__pycache__", ".pytest_cache"}


def tracked_paths(root: Path) -> list:
    """Tracked files from git; a scoped walk when git is not available."""
    try:
        out = subprocess.run(["git", "-C", str(root), "ls-files"], capture_output=True, text=True, check=True).stdout
        paths = out.splitlines()
    except (OSError, subprocess.CalledProcessError):
        paths = [p.relative_to(root).as_posix() for p in root.rglob("*") if p.is_file()]
    return [
        p for p in sorted(paths)
        if Path(p).suffix in TEXT_SUFFIXES and not SKIP_DIRS & set(Path(p).parts)
    ]


def read_texts(root: Path) -> dict:
    texts = {}
    for rel in tracked_paths(root):
        try:
            texts[rel] = (root / rel).read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
    return texts


def banned_failures(rel: str, text: str) -> list:
    failures = []
    for pattern, label, exempt in BANNED:
        if rel.startswith(exempt):
            continue
        for match in pattern.finditer(text):
            start = text.rfind("\n", 0, match.start()) + 1
            end = text.find("\n", match.end())
            if ALLOW_MARKER in text[start:end if end != -1 else len(text)]:
                continue
            failures.append(f"{rel}:{text.count(chr(10), 0, match.start()) + 1}: {label}")
    return failures


def required_failures(rel: str, text: str) -> list:
    return [f"{rel}: lacks {term}" for term in REQUIRED if term not in text]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("root", nargs="?", default=".")
    parser.add_argument("--owner-file", help="also check this file when it exists")
    args = parser.parse_args()
    root = Path(args.root)

    texts = read_texts(root)
    failures = []
    for rel, text in texts.items():
        failures += banned_failures(rel, text)
    for rel in SKILLS:
        if rel in texts:
            failures += required_failures(rel, texts[rel])
        else:
            failures.append(f"{rel}: missing")
    if args.owner_file and Path(args.owner_file).is_file():
        owner = Path(args.owner_file)
        text = owner.read_text(encoding="utf-8")
        label = str(owner)
        failures += banned_failures(label, text) + required_failures(label, text)

    for failure in failures:
        print("FAIL:", failure)
    if failures:
        return 1
    print("working-process: no stale terms, required terms present.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
