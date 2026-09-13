#!/usr/bin/env python3
"""check-references.py — find dangling doc/skill references in skills/**/SKILL.md.

Two rules, run over every skills/*/SKILL.md:

1. Path rule: a backticked token ending in `.md` must resolve — relative to
   its own skill directory, or relative to the repo root — UNLESS its
   basename is in ALLOWLIST and the referencing skill is one of the names
   sanctioned for that basename. The allowlist exists for files a skill
   legitimately expects to find in the *target* repo it is applied to
   (REVIEW.md, HANDOFF.md, ...), which never exist in this library itself.
   It is scoped per skill (not a blanket filename pass) so a skill that
   picks up a real file's name in the wrong sense (see prompt-eng's old
   `REVIEW.md` reference, which was never about a review-config file) still
   gets caught.

2. Skill-name rule: a backticked token matching `[a-z][a-z-]+` immediately
   preceded by "use ", "see ", or an arrow ("-> " / "→ ") must name a
   directory under skills/. A few short common words that occur in code
   snippets or examples (not skill references) are excluded explicitly
   below rather than guessed at.
"""
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SKILLS_DIR = REPO_ROOT / "skills"

# Rule 1: user-repo files a skill may legitimately expect to exist in the
# *target* repo, not in this library. Scoped per skill: only the skills
# listed here may reference the basename without it resolving to a real
# file. Add an entry only when you've confirmed the reference really means
# "this file may exist in the repo this skill runs in" — not just because
# the filename happens to match.
ALLOWLIST = {
    "REVIEW.md": {"deep-review"},
    "CLAUDE.md": {"deep-review"},
    "HANDOFF.md": {"handoff"},
    "AGENTS.md": set(),
    "WORKPLAN.md": {"apply-working-process"},
    "TASKS.md": {"breakdown"},
    "DECISIONS.md": {"apply-working-process"},
    "SPEC.md": {"spec"},
    ".claude/test-command": set(),
}

# Rule 2: words that match the skill-name shape and follow a trigger phrase
# but are not skill references (code identifiers, prose nouns caught inside
# an illustrative scenario). Verified by hand against the current corpus.
RULE2_ALLOWLIST_WORDS = {"total"}

PATH_TOKEN_RE = re.compile(r"^[A-Za-z0-9_][A-Za-z0-9_.\-]*(/[A-Za-z0-9_][A-Za-z0-9_.\-]*)*\.md$")
BACKTICK_RE = re.compile(r"`([^`\n]+)`")
RULE2_RE = re.compile(r"(?:use|see|→|->) `([a-z][a-z-]+)`")


def check_path_token(token: str, skill_name: str, skill_dir: Path) -> str | None:
    """Return a failure reason, or None if the token resolves or is out of scope."""
    if not PATH_TOKEN_RE.match(token):
        return None  # not a clean path-like token (spaces, placeholders, etc.)

    basename = token.rsplit("/", 1)[-1]
    sanctioned = ALLOWLIST.get(basename)
    if sanctioned is not None:
        if skill_name in sanctioned:
            return None
        return (
            f"`{token}` is only allowlisted for {sorted(sanctioned) or '(no skill yet)'} "
            f"as a target-repo file, not for `{skill_name}`"
        )

    if (skill_dir / token).exists() or (REPO_ROOT / token).exists():
        return None
    return f"`{token}` does not resolve relative to skills/{skill_name}/ or the repo root"


def check_skill_name_token(token: str, line: str) -> str | None:
    if token in RULE2_ALLOWLIST_WORDS:
        return None
    if not (SKILLS_DIR / token).is_dir():
        return f"`{token}` referenced as a skill but no skills/{token}/ directory exists"
    return None


def main() -> int:
    failures: list[str] = []

    for skill_md in sorted(SKILLS_DIR.glob("*/SKILL.md")):
        skill_dir = skill_md.parent
        skill_name = skill_dir.name
        lines = skill_md.read_text().splitlines()

        for lineno, line in enumerate(lines, start=1):
            for match in BACKTICK_RE.finditer(line):
                token = match.group(1)
                if token.endswith(".md"):
                    reason = check_path_token(token, skill_name, skill_dir)
                    if reason:
                        failures.append(f"{skill_md}:{lineno}: {reason}")

            for match in RULE2_RE.finditer(line):
                token = match.group(1)
                reason = check_skill_name_token(token, line)
                if reason:
                    failures.append(f"{skill_md}:{lineno}: {reason}")

    if failures:
        print(f"check-references.py: {len(failures)} dangling reference(s):")
        for f in failures:
            print(f"  {f}")
        return 1

    print("check-references.py: no dangling references found.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
