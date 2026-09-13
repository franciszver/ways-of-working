#!/usr/bin/env python3
"""check-skill-sections.py — closing-section and duplication checks for canonical skills.

For every skills/*/SKILL.md, checks:

  (a) Section spelling. Every `##` heading whose normalized text is one of
      "rules", "hard rules", "anti-patterns", "antipatterns", "pitfalls",
      or "failure modes" must be spelled exactly "## Rules" or
      "## Anti-patterns" — no other spelling.
  (b) Report section. Every skill named in REPORT_REQUIRED must contain a
      "## Report" section (numbering prefixes like "## 6. Report" count).
  (c) Near-duplicate paragraphs. Paragraphs of >= MIN_DUP_WORDS words are
      compared pairwise across different skills with word-shingle Jaccard
      overlap (SHINGLE_SIZE-word shingles); a pair scoring >= DUP_THRESHOLD
      is flagged. This catches paraphrases, not just byte-identical text.

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
SHINGLE_SIZE = 12
DUP_THRESHOLD = 0.5

# Normalized heading text -> the one spelling it must use.
SECTION_ALIASES = {
    "rules": "Rules",
    "hard rules": "Rules",
    "anti-patterns": "Anti-patterns",
    "antipatterns": "Anti-patterns",
    "pitfalls": "Anti-patterns",
    "failure modes": "Anti-patterns",
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
    annotation, then lowercase, for alias matching."""
    s = NUMBERING_RE.sub("", raw).strip()
    s = re.split(r"\s+—|\s+\(", s, maxsplit=1)[0].strip()
    return s.lower()


def check_headings(body: str, rel: str) -> list:
    errors = []
    for raw in HEADING_RE.findall(body):
        raw = raw.strip()
        norm = normalize_heading(raw)
        want = SECTION_ALIASES.get(norm)
        if want and raw != want:
            errors.append(
                f"{rel}: section '## {raw}' reads as {want} — spell it exactly '## {want}'"
            )
    return errors


def check_report_section(body: str, skill_name: str, rel: str) -> list:
    if skill_name not in REPORT_REQUIRED:
        return []
    for h in HEADING_RE.findall(body):
        if normalize_heading(h.strip()) == "report":
            return []
    return [f"{rel}: skill is in REPORT_REQUIRED but has no '## Report' section"]


def paragraphs(body: str) -> list:
    parts = re.split(r"\n\s*\n", body)
    out = []
    for p in parts:
        norm = re.sub(r"\s+", " ", p).strip()
        norm = re.sub(r"^#+\s*", "", norm)
        words = norm.split()
        if len(words) >= MIN_DUP_WORDS:
            out.append((norm, words))
    return out


def shingles(words: list, k: int = SHINGLE_SIZE) -> set:
    tokens = [w.lower().strip(".,;:!?\"'()") for w in words]
    if len(tokens) < k:
        return {tuple(tokens)}
    return {tuple(tokens[i:i + k]) for i in range(len(tokens) - k + 1)}


def jaccard(a: set, b: set) -> float:
    if not a and not b:
        return 0.0
    union = a | b
    if not union:
        return 0.0
    return len(a & b) / len(union)


def find_duplicates(entries: list) -> list:
    """entries: list of (rel, paragraph_text, word_list). Returns error strings
    for any cross-file pair scoring >= DUP_THRESHOLD."""
    errors = []
    shingle_sets = [shingles(words) for _, _, words in entries]
    n = len(entries)
    for i in range(n):
        rel_i, text_i, _ = entries[i]
        for j in range(i + 1, n):
            rel_j, text_j, _ = entries[j]
            if rel_i == rel_j:
                continue
            score = jaccard(shingle_sets[i], shingle_sets[j])
            if score >= DUP_THRESHOLD:
                snippet = text_i[:100] + ("…" if len(text_i) > 100 else "")
                errors.append(
                    f"near-duplicate paragraph (jaccard={score:.2f}, >= {DUP_THRESHOLD}) "
                    f"in {rel_i} and {rel_j}: \"{snippet}\""
                )
    return errors


def main() -> int:
    default_lib = Path(__file__).resolve().parent.parent
    lib = Path(sys.argv[1]) if len(sys.argv) > 1 else default_lib

    skill_dirs = _lib.skill_dirs(lib, "skills")
    if not skill_dirs:
        print(f"FAIL: 0 canonical skills found under {lib / 'skills'} — wrong LIB_ROOT?")
        return 1

    all_errors = []
    para_entries = []

    for d in skill_dirs:
        path = d / "SKILL.md"
        rel = str(path.relative_to(lib))
        raw = path.read_text(encoding="utf-8")
        body = strip_frontmatter_and_fences(raw)

        all_errors.extend(check_headings(body, rel))
        all_errors.extend(check_report_section(body, d.name, rel))

        for text, words in paragraphs(body):
            para_entries.append((rel, text, words))

    all_errors.extend(find_duplicates(para_entries))

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
