#!/usr/bin/env python3
"""gen-ports.py — regenerate the Antigravity workflow stubs and the
AGENTS.md skill pointer lines from skills/*/SKILL.md frontmatter, so both
always match the canonical descriptions verbatim.

Usage: python3 scripts/gen-ports.py [LIB_ROOT] [--check]
  --check: write nothing; exit 1 if regenerating would change any file
           (the CI drift check).
Requires PyYAML (exits 2 if missing).
"""
import re
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


def load_description(skill_dir: Path) -> str:
    text = (skill_dir / "SKILL.md").read_text()
    end = text.find("\n---", 4)
    data = yaml.safe_load(text[4:end])
    return str(data["description"])


MAX_TRIGGER = 110


def trigger_line(description: str) -> str:
    """The one-line trigger for AGENTS.md: the 'Use ...' clause, trimmed to
    its first sentence (drops trailing disambiguation asides), then to
    MAX_TRIGGER chars at a word boundary so the file stays compact."""
    idx = description.find("Use ")
    rest = description[idx:] if idx != -1 else description
    m = re.search(r"\.(?=\s|$)", rest)
    sentence = rest[: m.end()] if m else rest
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
        f"(or `.agent/skills/{name}/SKILL.md`). Apply it to: $ARGUMENTS\n"
    )


def gen_agents_md_block(names: list, descriptions: dict) -> str:
    lines = [AGENTS_MD_BEGIN]
    for name in names:
        lines.append(f"- @skills/{name}/SKILL.md — {trigger_line(descriptions[name])}")
    lines.append(AGENTS_MD_END)
    return "\n".join(lines)


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
    if AGENTS_MD_BEGIN not in text or AGENTS_MD_END not in text:
        print(f"FAIL: {agents_md} has no {AGENTS_MD_BEGIN}/{AGENTS_MD_END} markers")
        return 1
    block = gen_agents_md_block(names, descriptions)
    new_text = re.sub(
        re.escape(AGENTS_MD_BEGIN) + r".*?" + re.escape(AGENTS_MD_END),
        block,
        text,
        flags=re.DOTALL,
    )
    if new_text != text:
        changed.append(str(agents_md.relative_to(lib)))
        if not check_only:
            agents_md.write_text(new_text)

    if check_only:
        if changed:
            print("Regenerating would change:")
            for c in changed:
                print(f"  {c}")
            return 1
        print("gen-ports: no drift.")
        return 0

    print(f"Regenerated {len(changed)} file(s):" if changed else "Nothing to regenerate.")
    for c in changed:
        print(f"  {c}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
