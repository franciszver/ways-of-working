#!/usr/bin/env python3
"""check-counts.py — README.md's stated skill count must match disk.

Derives the canonical skill count from skills/*/SKILL.md and checks that
README.md's map line says "<N> canonical skills" with the same N.
Exits 1 on mismatch.
"""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import _lib

PATTERN = re.compile(r"(\d+) canonical skills")


def main() -> int:
    lib = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.cwd()
    actual = len(_lib.skill_names(lib, "skills"))

    readme = (lib / "README.md").read_text()
    matches = PATTERN.findall(readme)
    if not matches:
        print("FAIL: README.md has no '<N> canonical skills' line")
        return 1

    stated_values = sorted({int(m) for m in matches})
    print(f"Actual canonical skill count: {actual}")
    print(f"README.md states: {', '.join(str(v) for v in stated_values)} ({len(matches)} occurrence(s))")
    mismatches = [int(m) for m in matches if int(m) != actual]
    if mismatches:
        print(f"FAIL: README.md has {len(mismatches)} occurrence(s) not equal to actual ({actual})")
        return 1

    print("Count matches.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
