#!/usr/bin/env python3
"""check-counts.py — README.md's stated skill count must match disk.

Derives the canonical skill count from skills/*/SKILL.md and checks that
README.md's map line says "<N> canonical skills" with the same N.
Exits 1 on mismatch.
"""
import re
import sys
from pathlib import Path

PATTERN = re.compile(r"(\d+) canonical skills")


def main() -> int:
    lib = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.cwd()
    actual = sum(1 for d in (lib / "skills").iterdir() if d.is_dir() and (d / "SKILL.md").is_file())

    readme = (lib / "README.md").read_text()
    match = PATTERN.search(readme)
    if not match:
        print("FAIL: README.md has no '<N> canonical skills' line")
        return 1

    stated = int(match.group(1))
    print(f"Actual canonical skill count: {actual}")
    print(f"README.md states: {stated}")
    if stated != actual:
        print(f"FAIL: README.md says {stated} canonical skills, actual is {actual}")
        return 1

    print("Count matches.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
