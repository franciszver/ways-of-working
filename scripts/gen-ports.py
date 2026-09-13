#!/usr/bin/env python3
"""gen-ports.py — regenerate the Antigravity workflow stubs and the
AGENTS.md skill pointer lines from skills/*/SKILL.md frontmatter, so both
always match the canonical descriptions verbatim.

Usage: python3 scripts/gen-ports.py [LIB_ROOT] [--check]
  --check: write nothing; exit 1 if regenerating would change any file,
           or if AGENTS.md would carry anything but exactly one
           `@skills/<name>/SKILL.md` line per canonical skill (the CI
           drift + uniqueness check).
Requires PyYAML (exits 2 if missing, via _lib.parse_frontmatter).

A workflow stub's skill path (`.agents/skills/<name>/SKILL.md` or
`.agent/skills/<name>/SKILL.md`) must match install.sh's ANTIGRAVITY_DIR
(".agents") and ANTIGRAVITY_LEGACY_DIR (".agent") — keep the two in sync.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import _lib

try:
    import yaml  # type: ignore
except ImportError:
    print("FAIL: PyYAML is required (pip install pyyaml)", file=sys.stderr)
    raise SystemExit(2)

AGENTS_MD_BEGIN = "<!-- gen-ports:skills:begin -->"
AGENTS_MD_END = "<!-- gen-ports:skills:end -->"

# Sentence-boundary periods that must NOT be treated as a sentence end when
# scanning a description for its trigger clause.
ABBREVIATIONS = ("e.g", "i.e", "etc", "vs")

# Safety net only — real trigger clauses run well under this. Guards
# against a future description with no sentence-ending period at all.
MAX_TRIGGER = 400

# AGENTS.md is meant to stay compact; regeneration fails above this so a
# runaway description is caught here, not discovered by a human later.
MAX_AGENTS_MD_BYTES = 12 * 1024


def load_description(skill_dir: Path) -> str:
    data = _lib.parse_frontmatter(skill_dir / "SKILL.md")
    return str(data["description"])


def sentence_end(text: str) -> int:
    """Index just past the first real sentence-ending period in text,
    skipping periods that belong to a known abbreviation (e.g., i.e.,
    etc., vs.). Falls back to len(text) if no such period exists."""
    i = 0
    while True:
        idx = text.find(".", i)
        if idx == -1:
            return len(text)
        if any(text[:idx].endswith(abbr) for abbr in ABBREVIATIONS):
            i = idx + 1
            continue
        if idx + 1 == len(text) or text[idx + 1].isspace():
            return idx + 1
        i = idx + 1


def trigger_line(description: str) -> str:
    """The one-line trigger for AGENTS.md: the whole 'Use ...' sentence,
    never cut mid-clause except by the MAX_TRIGGER safety net."""
    idx = description.find("Use ")
    rest = description[idx:] if idx != -1 else description
    sentence = rest[: sentence_end(rest)]
    if len(sentence) <= MAX_TRIGGER:
        return sentence
    cut = sentence[:MAX_TRIGGER].rsplit(" ", 1)[0]
    return cut.rstrip(",;") + "…"


def gen_workflow(name: str, description: str) -> str:
    front = yaml.safe_dump(
        {"description": description}, default_flow_style=False, allow_unicode=True, width=1 << 20
    ).rstrip("\n")
    return (
        f"---\n{front}\n---\n\n"
        f"Load and follow the skill at `.agents/skills/{name}/SKILL.md` "
        f"(or `.agent/skills/{name}/SKILL.md`). Apply it to the argument given with the command.\n"
    )


def gen_agents_md_block(names: list, descriptions: dict) -> str:
    lines = [AGENTS_MD_BEGIN]
    for name in names:
        lines.append(f"- @skills/{name}/SKILL.md — {trigger_line(descriptions[name])}")
    lines.append(AGENTS_MD_END)
    return "\n".join(lines)


def splice_block(text: str, block: str) -> str:
    """Replace the gen-ports:skills marker span with block, via plain
    string search-and-splice (no regex — a description could contain
    regex-special characters that re.sub would misread as a replacement
    backreference)."""
    begin = text.find(AGENTS_MD_BEGIN)
    end = text.find(AGENTS_MD_END)
    if begin == -1 or end == -1:
        raise ValueError(f"missing {AGENTS_MD_BEGIN}/{AGENTS_MD_END} markers")
    end += len(AGENTS_MD_END)
    return text[:begin] + block + text[end:]


def check_agents_md_uniqueness(text: str, names: list) -> list:
    """Each canonical skill must appear as exactly one @skills/<name>/SKILL.md
    line in the whole file — not zero, not duplicated."""
    errors = []
    for name in names:
        count = text.count(f"@skills/{name}/SKILL.md")
        if count != 1:
            errors.append(f"@skills/{name}/SKILL.md appears {count} time(s), expected 1")
    return errors


def main() -> int:
    default_lib = Path(__file__).resolve().parent.parent
    check_only = "--check" in sys.argv
    positional = [a for a in sys.argv[1:] if not a.startswith("--")]
    lib = Path(positional[0]) if positional else default_lib

    canonical = _lib.skill_dirs(lib, "skills")
    if not canonical:
        print(f"FAIL: 0 canonical skills found under {lib / 'skills'} — wrong LIB_ROOT?")
        return 1

    descriptions = {d.name: load_description(d) for d in canonical}
    names = sorted(descriptions)
    changed = []

    workflows_dir = lib / "antigravity" / "workflows"
    workflows_dir.mkdir(parents=True, exist_ok=True)
    for name in names:
        target = workflows_dir / f"{name}.md"
        content = gen_workflow(name, descriptions[name])
        if not target.is_file() or target.read_text() != content:
            changed.append(str(target.relative_to(lib)))
            if not check_only:
                target.write_text(content)

    agents_md = lib / "ports" / "agents-md" / "AGENTS.md"
    text = agents_md.read_text()
    block = gen_agents_md_block(names, descriptions)
    try:
        new_text = splice_block(text, block)
    except ValueError as e:
        print(f"FAIL: {agents_md}: {e}")
        return 1

    new_bytes = len(new_text.encode("utf-8"))
    if new_bytes > MAX_AGENTS_MD_BYTES:
        print(f"FAIL: regenerating {agents_md} would produce {new_bytes} bytes, over the {MAX_AGENTS_MD_BYTES}-byte cap.")
        return 1

    if new_text != text:
        changed.append(str(agents_md.relative_to(lib)))
        if not check_only:
            agents_md.write_text(new_text)

    uniqueness_errors = check_agents_md_uniqueness(new_text if check_only else agents_md.read_text(), names)

    if check_only:
        ok = True
        if changed:
            ok = False
            print("Regenerating would change:")
            for c in changed:
                print(f"  {c}")
        if uniqueness_errors:
            ok = False
            print("AGENTS.md pointer uniqueness FAILED:")
            for e in uniqueness_errors:
                print(f"  {e}")
        if ok:
            print(f"gen-ports: no drift. {agents_md.relative_to(lib)} is {new_bytes} bytes.")
            return 0
        return 1

    if uniqueness_errors:
        print("AGENTS.md pointer uniqueness FAILED:")
        for e in uniqueness_errors:
            print(f"  {e}")
        return 1

    print(f"Regenerated {len(changed)} file(s):" if changed else "Nothing to regenerate.")
    for c in changed:
        print(f"  {c}")
    print(f"{agents_md.relative_to(lib)} is {new_bytes} bytes.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
