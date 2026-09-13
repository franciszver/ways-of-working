#!/usr/bin/env python3
"""stamp-provenance.py — write or update a skills-local provenance marker.

Every skills-local/<name>/SKILL.md twin backed by a canonical skill
(skills/<name>/SKILL.md exists) carries, right after its frontmatter:

    <!-- local: derived-from: skills/<name>/SKILL.md@<sha256, first 12 hex> -->

scripts/check_parity.py fails a twin with no such marker (MISSING
PROVENANCE) or whose marker's hash no longer matches the canonical file's
current hash (STALE — canonical changed since the twin was derived). This
script writes or updates the marker in one command, so re-deriving a twin
never means hand-computing a hash.

Usage: python3 scripts/stamp-provenance.py --all | <name> [<name> ...] [LIB_ROOT]
  --all   stamp every skills-local twin that has a canonical counterpart.
  <name>  stamp only the named skill(s) — must exist under both skills/
          and skills-local/.
LIB_ROOT: optional, as the last argument, if it names an existing
directory; defaults to the repo root (the parent of this scripts/ dir).
"""
import hashlib
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import _lib

MARKER_PREFIX = "<!-- local: derived-from: skills/"


def canonical_hash(canonical_file: Path) -> str:
    return hashlib.sha256(canonical_file.read_bytes()).hexdigest()[:12]


def stamp_one(lib: Path, name: str) -> bool:
    canonical_file = lib / "skills" / name / "SKILL.md"
    twin_file = lib / "skills-local" / name / "SKILL.md"
    if not canonical_file.is_file():
        print(f"SKIP {name}: no canonical skills/{name}/SKILL.md")
        return False
    if not twin_file.is_file():
        print(f"SKIP {name}: no skills-local/{name}/SKILL.md")
        return False

    frontmatter_text, body = _lib.split_frontmatter(twin_file)
    digest = canonical_hash(canonical_file)
    marker_line = f"<!-- local: derived-from: skills/{name}/SKILL.md@{digest} -->\n"

    # Drop any existing provenance marker line wherever it sits; keep
    # everything else (blank lines, a deliberate-divergence comment).
    body_lines = body.splitlines(keepends=True)
    kept = [ln for ln in body_lines if not ln.strip().startswith(MARKER_PREFIX)]

    # Re-insert right after the frontmatter: past any leading blank
    # line(s), before the first real content line, followed by every
    # other HTML comment already sitting there (e.g. a deliberate-
    # divergence note) and then one blank line before the first
    # non-comment content, so a heading never sits flush against a
    # comment block.
    idx = 0
    while idx < len(kept) and kept[idx].strip() == "":
        idx += 1
    leading_blank = "\n" if idx > 0 else ""  # collapse any run of leading
    # blanks to at most one, so re-stamping never grows the gap left
    # behind by the marker line this pass just removed.
    comment_end = idx
    while comment_end < len(kept) and kept[comment_end].strip().startswith("<!--"):
        comment_end += 1
    needs_blank = comment_end < len(kept) and kept[comment_end].strip() != ""
    new_body = (
        leading_blank
        + marker_line
        + "".join(kept[idx:comment_end])
        + ("\n" if needs_blank else "")
        + "".join(kept[comment_end:])
    )

    twin_file.write_text(f"---\n{frontmatter_text}---\n{new_body}", encoding="utf-8")
    print(f"stamped {name}: {digest}")
    return True


def main() -> int:
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        return 2

    default_lib = Path(__file__).resolve().parent.parent
    lib = default_lib
    if args[-1] != "--all" and Path(args[-1]).is_dir():
        lib = Path(args[-1])
        args = args[:-1]

    if "--all" in args:
        names = sorted(_lib.skill_names(lib, "skills") & _lib.skill_names(lib, "skills-local"))
    else:
        names = args

    if not names:
        print("FAIL: no skills to stamp")
        return 1

    ok = True
    for name in names:
        if not stamp_one(lib, name):
            ok = False
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
