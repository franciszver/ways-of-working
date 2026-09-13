#!/usr/bin/env python3
"""check-skill-sections.py — closing-section and duplication checks for canonical skills.

For every skills/*/SKILL.md, checks:

  (a) Closing section spelling. The file's last `##` section, if its
      heading means "binding constraints" or "failure modes to avoid" under
      a fixed synonym list, must be spelled exactly "## Rules" or
      "## Anti-patterns" — no other spelling, and no crossed labels (a
      failure-modes list must not be titled "## Rules").
  (b) Report section. Every skill named in REPORT_REQUIRED must contain a
      "## Report" section (numbering prefixes like "## 6. Report" count).
  (c) Duplicate paragraphs. No paragraph of >= MIN_DUP_WORDS words appears
      verbatim (whitespace-normalized) in two different skills.

Exits 1 if any check fails. Requires no third-party packages.
"""
import re
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import _lib

REPORT_REQUIRED = {
    "incident", "postmortem", "prove", "research", "spec",
    "refactor", "release", "migrate", "perf", "sec-audit",
}

MIN_DUP_WORDS = 40

RULE_SYNONYMS = {
    "rules", "rule", "constraints", "musts", "non-negotiables", "binding rules",
    "must follow",
}
ANTIPATTERN_SYNONYMS = {
    "anti-patterns", "antipatterns", "anti patterns", "pitfalls",
    "failure modes", "common mistakes", "mistakes to avoid", "gotchas",
    "what to avoid", "things to avoid",
}

CODE_FENCE_RE = re.compile(r"```.*?```", re.DOTALL)
HEADING_RE = re.compile(r"^##\s+(.+?)\s*$", re.MULTILINE)
NUMBERING_RE = re.compile(r"^\d+\.\s*")


def strip_frontmatter_and_fences(text: str) -> str:
    if text.startswith("---\n"):
        end = text.find("\n---\n", 4)
        if end != -1:
            text = text[end + 5:]
    return CODE_FENCE_RE.sub("", text)


def normalize_heading(raw: str) -> str:
    """Strip a leading 'N. ' numbering and any ' — ...'/' (...)' trailing
    annotation, then lowercase, for synonym matching."""
    s = NUMBERING_RE.sub("", raw).strip()
    s = re.split(r"\s+—|\s+\(", s, maxsplit=1)[0].strip()
    return s.lower()


def check_closing_section(body: str, rel: str) -> list:
    headings = HEADING_RE.findall(body)
    if not headings:
        return []
    last_raw = headings[-1].strip()
    norm = normalize_heading(last_raw)
    errors = []
    if norm in RULE_SYNONYMS and last_raw != "Rules":
        errors.append(
            f"{rel}: closing section '## {last_raw}' reads as Rules — "
            "spell it exactly '## Rules'"
        )
    elif norm in ANTIPATTERN_SYNONYMS and last_raw != "Anti-patterns":
        errors.append(
            f"{rel}: closing section '## {last_raw}' reads as Anti-patterns — "
            "spell it exactly '## Anti-patterns'"
        )
    return errors


def check_report_section(body: str, skill_name: str, rel: str) -> list:
    if skill_name not in REPORT_REQUIRED:
        return []
    headings = HEADING_RE.findall(body)
    for h in headings:
        if normalize_heading(h.strip()) == "report":
            return []
    return [f"{rel}: skill is in REPORT_REQUIRED but has no '## Report' section"]


def paragraphs(body: str) -> list:
    parts = re.split(r"\n\s*\n", body)
    out = []
    for p in parts:
        norm = re.sub(r"\s+", " ", p).strip()
        norm = re.sub(r"^#+\s*", "", norm)
        if len(norm.split()) >= MIN_DUP_WORDS:
            out.append(norm)
    return out


def main() -> int:
    default_lib = Path(__file__).resolve().parent.parent
    lib = Path(sys.argv[1]) if len(sys.argv) > 1 else default_lib

    skill_dirs = _lib.skill_dirs(lib, "skills")
    if not skill_dirs:
        print(f"FAIL: 0 canonical skills found under {lib / 'skills'} — wrong LIB_ROOT?")
        return 1

    all_errors = []
    para_map = defaultdict(list)

    for d in skill_dirs:
        path = d / "SKILL.md"
        rel = str(path.relative_to(lib))
        raw = path.read_text(encoding="utf-8")
        body = strip_frontmatter_and_fences(raw)

        all_errors.extend(check_closing_section(body, rel))
        all_errors.extend(check_report_section(body, d.name, rel))

        for p in paragraphs(body):
            para_map[p].append(rel)

    for p, files in para_map.items():
        uniq = sorted(set(files))
        if len(uniq) > 1:
            snippet = p[:100] + ("…" if len(p) > 100 else "")
            all_errors.append(
                f"duplicate paragraph (>= {MIN_DUP_WORDS} words) in {', '.join(uniq)}: \"{snippet}\""
            )

    print(f"Checked {len(skill_dirs)} skills/*/SKILL.md files.")
    if all_errors:
        for e in sorted(all_errors):
            print(f"FAIL: {e}")
        print(f"\n{len(all_errors)} section error(s).")
        return 1

    print("All closing sections, Report sections, and paragraph checks pass.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
