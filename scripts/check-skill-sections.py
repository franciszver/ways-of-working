#!/usr/bin/env python3
"""check-skill-sections.py — closing-section, duplication, and reference checks.

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

For every skills/*/SKILL.md and skills-local/*/SKILL.md, plus each pack's
skills/*/references/*.md, check_references (below) checks:

  (d) Path rule. A backticked token ending in `.md` must resolve — against
      the referencing file's own directory, its skill's directory, or the
      repo root — UNLESS its basename is in REFERENCE_ALLOWLIST and the
      referencing (pack, skill) pair is one of the ones sanctioned for
      that basename. The allowlist exists for files a skill legitimately
      expects to find in the *target* repo it runs in (REVIEW.md,
      HANDOFF.md, ...), which never exist in this library. Resolution is
      tried first; the allowlist only excuses a token that didn't resolve,
      so a skill that names a real file's basename in the wrong sense (see
      prompt-eng's old `REVIEW.md` reference, which was never about a
      review-config file) still gets caught.
  (e) Skill-name rule. A backticked token matching `[a-z][a-z-]+`
      immediately preceded by "use ", "see ", or an arrow ("->"/"→")
      must name a directory in the pack being scanned (skills/ names for a
      skills/ file, skills-local/ names for a skills-local/ file).

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

PACKS = ("skills", "skills-local")

# Reference-rule (d): user-repo files a skill may legitimately expect to
# exist in the *target* repo, not in this library. Scoped per (pack,
# skill): only the pairs listed here may reference the basename without
# it resolving to a real file. Add an entry only when you've confirmed the
# reference really means "this file may exist in the repo/install this
# skill runs in" — not just because the filename happens to match.
REFERENCE_ALLOWLIST = {
    "REVIEW.md": {("skills", "deep-review"), ("skills-local", "deep-review")},
    "CLAUDE.md": {("skills", "deep-review")},
    "HANDOFF.md": {("skills", "handoff"), ("skills-local", "handoff")},
    "WORKPLAN.md": {("skills", "apply-working-process"), ("skills-local", "apply-working-process")},
    "TASKS.md": {("skills", "breakdown")},
    "DECISIONS.md": {("skills", "apply-working-process"), ("skills-local", "apply-working-process")},
    "SPEC.md": {("skills", "spec"), ("skills-local", "spec")},
    "ROUTING.md": {("skills", "apply-working-process")},
}

# Reference-rule (e): words that match the skill-name shape and follow a
# trigger phrase but are not skill references (code identifiers, prose
# nouns caught inside an illustrative scenario). Verified by hand against
# the current corpus.
REFERENCE_RULE2_ALLOWLIST_WORDS = {"total"}

REFERENCE_PATH_TOKEN_RE = re.compile(
    r"^(?:~|[A-Za-z0-9_.][A-Za-z0-9_.\-]*)(?:/[A-Za-z0-9_.][A-Za-z0-9_.\-]*)*\.md$"
)
REFERENCE_BACKTICK_RE = re.compile(r"`([^`\n]+)`")
REFERENCE_TRIGGER_RE = re.compile(r"(?i)\b(?:use|see|→|->)\s*$")

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


def _strip_frontmatter_lines(raw: str) -> tuple:
    """Blank the frontmatter fence, preserving line numbers. Returns
    (text_without_frontmatter_lines, lines_removed_from_the_top)."""
    lines = raw.splitlines(keepends=True)
    if lines and lines[0].rstrip("\n\r") == "---":
        for i in range(1, len(lines)):
            if lines[i].rstrip("\n\r") == "---":
                return "".join(lines[i + 1:]), i + 1
    return raw, 0


def _blank_fences_preserve_lines(text: str) -> str:
    """Blank out fenced code-block lines (``` ... ```), preserving line count."""
    out = []
    in_fence = False
    for line in text.splitlines(keepends=True):
        if line.strip().startswith("```"):
            in_fence = not in_fence
            out.append("\n")
        elif in_fence:
            out.append("\n")
        else:
            out.append(line)
    return "".join(out)


def _reference_scan_targets(lib: Path) -> list:
    """List of (pack, skill_name, skill_dir, file_path) to scan: every
    pack's SKILL.md plus each skill's references/*.md."""
    targets = []
    for pack in PACKS:
        for d in _lib.skill_dirs(lib, pack):
            targets.append((pack, d.name, d, d / "SKILL.md"))
            refs_dir = d / "references"
            if refs_dir.is_dir():
                for f in sorted(refs_dir.glob("*.md")):
                    targets.append((pack, d.name, d, f))
    return targets


def _check_reference_path_token(token: str, pack: str, skill_name: str, skill_dir: Path, file_dir: Path, lib: Path):
    bases = []
    for b in (file_dir, skill_dir, lib):
        if b not in bases:
            bases.append(b)
    if any((b / token).exists() for b in bases):
        return None
    basename = token.rsplit("/", 1)[-1]
    sanctioned = REFERENCE_ALLOWLIST.get(basename, set())
    if (pack, skill_name) in sanctioned:
        return None
    if sanctioned:
        allowed = ", ".join(f"{p}/{n}" for p, n in sorted(sanctioned))
        return f"`{token}` does not resolve, and is only allowlisted for {allowed}, not for {pack}/{skill_name}"
    return f"`{token}` does not resolve relative to {pack}/{skill_name}/ or the repo root"


def _check_reference_skill_name_token(token: str, pack: str, names_in_pack: set):
    if token in REFERENCE_RULE2_ALLOWLIST_WORDS:
        return None
    if token not in names_in_pack:
        return f"`{token}` referenced as a skill but no {pack}/{token}/ directory exists"
    return None


def check_references(lib: Path) -> tuple:
    """Returns (errors, scanned_file_count) for reference rules (d) and (e)."""
    errors = []
    targets = _reference_scan_targets(lib)
    names_by_pack = {pack: _lib.skill_names(lib, pack) for pack in PACKS}

    for pack, skill_name, skill_dir, path in targets:
        rel = str(path.relative_to(lib))
        raw = path.read_text(encoding="utf-8")
        body, offset = _strip_frontmatter_lines(raw)
        body = _blank_fences_preserve_lines(body)

        for idx, line in enumerate(body.splitlines(), start=1):
            lineno = idx + offset
            for match in REFERENCE_BACKTICK_RE.finditer(line):
                token = match.group(1)
                if token.endswith(".md"):
                    if not REFERENCE_PATH_TOKEN_RE.match(token):
                        continue  # not a clean path-like token (spaces, placeholders, etc.)
                    reason = _check_reference_path_token(token, pack, skill_name, skill_dir, path.parent, lib)
                elif REFERENCE_TRIGGER_RE.search(line[:match.start()]) and re.fullmatch(r"[a-z][a-z-]+", token):
                    reason = _check_reference_skill_name_token(token, pack, names_by_pack[pack])
                else:
                    continue
                if reason:
                    errors.append(f"{rel}:{lineno}: {reason}")

    return errors, len(targets)


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

    reference_errors, scanned_count = check_references(lib)
    if scanned_count == 0:
        print(f"FAIL: 0 files scanned for references under {lib} — wrong LIB_ROOT?")
        return 1
    all_errors.extend(reference_errors)

    print(f"Checked {len(skill_dirs)} skills/*/SKILL.md files.")
    print(f"Scanned {scanned_count} files for dangling references (skills/, skills-local/, */references/*.md).")
    if all_errors:
        for e in sorted(all_errors):
            print(f"FAIL: {e}")
        print(f"\n{len(all_errors)} section/reference error(s).")
        return 1

    print("All closing sections, Report sections, paragraph, and reference checks pass.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
