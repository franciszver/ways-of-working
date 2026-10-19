#!/usr/bin/env python3
"""check-working-process.py: no stale working-process terms, required terms present.

Usage: check-working-process.py [ROOT] [--owner-file PATH]

This is a tripwire, not proof that the rules are followed.

Checks:
  - No tracked text file names the old plan file or the old decision log,
    says "three gates" (also "3 gates", also across a line break), or
    tells the reader to keep a decisions log.
  - The canonical skill and its local twin name .agent/execution-plan.md,
    clean-code, ste-writing, plain-language, and "Four gates".
  - With --owner-file PATH, the same checks run on that file when it exists.
    An absent owner file is skipped silently.

Scope:
  - Tracked files only (git ls-files -z). Untracked files are not scanned.
  - Top-level build/ is skipped: build-profile.py --check covers it.
  - Tracked symlinks are skipped, so nothing outside the repo is read.
  - A file that cannot be read or decoded as UTF-8 is a failure.

Allow rule:
  - An exempt entry is an exact file path, or a directory prefix that ends
    with "/". "CHANGELOG.md" does not exempt "CHANGELOG.mdx".
  - CHANGELOG.md and PLAN.md keep history.
  - This script and its test hold stale terms on purpose.
  - A line may carry the marker "check-working-process: allow".

Known limits, not caught:
  - Gate order swaps.
  - A required term mentioned once, out of context.
  - Untracked files.

Exits 1 on any failure.
"""
import argparse
import re
import subprocess
import sys
from pathlib import Path

ALLOW_MARKER = "check-working-process: allow"
HISTORY_FILES = ("CHANGELOG.md", "PLAN.md")
SELF_FILES = ("scripts/check-working-process.py", "scripts/test-check-working-process.sh")
EXEMPT_COMMON = HISTORY_FILES + SELF_FILES

# (pattern, label, exempt paths). BANNED patterns ignore case, because a
# stale phrase is stale in any case. REQUIRED terms match exactly, because
# they are names: the skill is `clean-code`, the heading is "Four gates".
BANNED = [
    (re.compile(r"WORKPLAN\.md", re.IGNORECASE), "names the old plan file", EXEMPT_COMMON),
    (re.compile(r"CURR-AGENT-EFFORT(?:\.md)?", re.IGNORECASE), "names the old effort-plan file", EXEMPT_COMMON),
    (re.compile(r"DECISIONS\.md|prd/DECISIONS", re.IGNORECASE), "names the old decision log", EXEMPT_COMMON),
    (re.compile(r"\b(?:three|3)[-\s]+gates?\b", re.IGNORECASE), 'says "three gates"', EXEMPT_COMMON),
    (re.compile(r"\bkeeps?\s+a\s+decisions?\s+log\b", re.IGNORECASE), "tells the reader to keep a decisions log", EXEMPT_COMMON),
    (re.compile(r"\bsame-session\s+decision", re.IGNORECASE), "names same-session decision logging", EXEMPT_COMMON),
]
REQUIRED = [".agent/execution-plan.md", "clean-code", "ste-writing", "plain-language", "Four gates"]
REQUIRED_FILES = ["skills/apply-working-process/SKILL.md", "skills-local/apply-working-process/SKILL.md"]
TEXT_SUFFIXES = {".md", ".mdc", ".mdx", ".py", ".sh", ".json", ".yaml", ".yml", ".txt", ".toml"}
SKIPPED_TOP_DIRS = {".git", "build", "node_modules"}


def is_exempt(rel: str, exempt: tuple) -> bool:
    """Exact file path, or a directory prefix ending in "/"."""
    return any(rel == e or (e.endswith("/") and rel.startswith(e)) for e in exempt)


def line_of(text: str, pos: int) -> int:
    return text.count("\n", 0, pos) + 1


def list_files(root: Path) -> list:
    """Tracked files from git, NUL-split. A walk when git is not available."""
    try:
        out = subprocess.run(["git", "-C", str(root), "ls-files", "-z"], capture_output=True, check=True).stdout
        names = [n.decode("utf-8", "surrogateescape") for n in out.split(b"\0") if n]
    except (OSError, subprocess.CalledProcessError):
        names = [p.relative_to(root).as_posix() for p in root.rglob("*") if p.is_file()]
    return sorted(n for n in names if scannable(root, n))


def scannable(root: Path, rel: str) -> bool:
    path = Path(rel)
    return (
        path.suffix in TEXT_SUFFIXES
        and path.parts[0] not in SKIPPED_TOP_DIRS
        and not (root / rel).is_symlink()
    )


def read_text(path: Path, label: str):
    """Return (text, None) or (None, failure message with the real cause)."""
    try:
        return path.read_text(encoding="utf-8"), None
    except (OSError, UnicodeDecodeError) as err:
        return None, f"{label}: unreadable ({err})"


def banned_failures(rel: str, text: str, exempt_applies: bool = True) -> list:
    failures = []
    lines = text.split("\n")
    for pattern, label, exempt in BANNED:
        if exempt_applies and is_exempt(rel, exempt):
            continue
        for match in pattern.finditer(text):
            first, last = line_of(text, match.start()), line_of(text, match.end())
            if any(ALLOW_MARKER in line for line in lines[first - 1:last]):
                continue
            failures.append(f"{rel}:{first}: {label}")
    return failures


def required_failures(rel: str, text: str) -> list:
    return [f"{rel}: lacks {term}" for term in REQUIRED if term not in text]


def collect_failures(root: Path, owner_file=None) -> list:
    failures = []
    names = list_files(root)
    readable = {}
    for rel in names:
        text, error = read_text(root / rel, rel)
        if error:
            failures.append(error)
        else:
            readable[rel] = text
            failures += banned_failures(rel, text)

    for rel in REQUIRED_FILES:
        if rel in readable:
            failures += required_failures(rel, readable[rel])
        elif rel not in names:
            failures.append(f"{rel}: missing")

    if owner_file and Path(owner_file).is_file():
        text, error = read_text(Path(owner_file), str(owner_file))
        if error:
            failures.append(error)
        else:
            failures += banned_failures(str(owner_file), text, exempt_applies=False)
            failures += required_failures(str(owner_file), text)
    return failures


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("root", nargs="?", default=".")
    parser.add_argument("--owner-file", help="also check this file when it exists")
    args = parser.parse_args()

    failures = collect_failures(Path(args.root), args.owner_file)
    for failure in failures:
        print("FAIL:", failure)
    if failures:
        return 1
    print("working-process: no stale terms, required terms present.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
