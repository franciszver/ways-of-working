#!/usr/bin/env python3
"""check-plain-language.py: the plain-language skill must strike em dashes
and must carry no refresh schedule.

Checks, all grep-style:
  1. SKILL.md and both references hold no refresh-schedule text.
  2. SKILL.md has no text that tolerates em dashes.
  3. The check order names em dashes.
  4. The em-dash section and the check order hold no U+2014 themselves.
  5. The description names AI-writing tells and clear technical English.
Exits 1 on any failure.
"""
import re
import sys
from pathlib import Path

EM_DASH = "—"
REFRESH = re.compile(r"refresh", re.IGNORECASE)
TOLERATES = [
    re.compile(r"not reliable tells", re.IGNORECASE),
    re.compile(r"drive the\s+count\s+to\s+zero", re.IGNORECASE),
    re.compile(r"zero-dash preference", re.IGNORECASE),
    re.compile(r"style preference, not\s+evidence", re.IGNORECASE),
]


def section(text: str, heading_start: str) -> str:
    """Return the body of the '## ' section whose heading starts with heading_start."""
    m = re.search(r"^## " + re.escape(heading_start) + r".*?$(.*?)(?=^## |\Z)", text, re.S | re.M)
    return m.group(1) if m else ""


def main() -> int:
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.cwd()
    base = root / "skills" / "plain-language"
    files = [base / "SKILL.md", base / "references" / "wp-aisigns.md", base / "references" / "ai-tells.md"]
    failures = []

    for f in files:
        text = f.read_text()
        for n, line in enumerate(text.splitlines(), 1):
            if REFRESH.search(line):
                failures.append(f"{f.relative_to(root)}:{n}: refresh-schedule text: {line.strip()[:70]}")

    skill = files[0].read_text()
    for pat in TOLERATES:
        if pat.search(skill):
            failures.append(f"SKILL.md: text that tolerates em dashes: /{pat.pattern}/")

    order = section(skill, "Check order")
    if not re.search(r"em[ -]dash", order, re.IGNORECASE):
        failures.append("SKILL.md: the check order does not name em dashes")
    if EM_DASH in order:
        failures.append("SKILL.md: the check order holds an em dash")

    dash_section = section(skill, "Em dashes")
    if not dash_section:
        failures.append("SKILL.md: no '## Em dashes' section")
    elif not re.search(r"\b(strike|remove)\b", dash_section, re.IGNORECASE):
        failures.append("SKILL.md: the em-dash section does not say to strike or remove them")
    if EM_DASH in dash_section:
        failures.append("SKILL.md: the em-dash section holds an em dash")

    desc = re.search(r"^description:\s*(.*)$", skill, re.M)
    d = desc.group(1) if desc else ""
    if "AI-writing tells" not in d or "clear technical English" not in d:
        failures.append("SKILL.md: description lacks 'AI-writing tells' or 'clear technical English'")
    if len(d) >= 1024:
        failures.append(f"SKILL.md: description is {len(d)} chars; limit is 1,023")

    for f in failures:
        print("FAIL:", f)
    if failures:
        return 1
    print("plain-language: em dashes struck, no refresh schedule.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
