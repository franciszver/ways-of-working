#!/usr/bin/env python3
"""Parity check: canonical skill names (skills/*/SKILL.md) vs every port.

Usage: python3 scripts/check_parity.py [LIB_ROOT]
LIB_ROOT defaults to the repo root (the parent of this scripts/ dir).
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import _lib

# Known filename-vs-skill-name divergence in the Cursor port. Cursor rule
# files predate some canonical skill names; this maps the rule's filename
# stem to the canonical skill it implements.
CURSOR_ALIAS = {
    "debugging": "debug",
    "reviewing": "deep-review",
    "verification": "prove",
    "security": "sec-audit",
    "performance": "perf",
    "codebase-research": "research-codebase",
    "brainstorming": "brainstorm",
    "estimation": "estimate",
    "explaining": "explain",
    "incidents": "incident",
    "migrations": "migrate",
    "onboarding": "onboard",
    "postmortems": "postmortem",
    "prompt-engineering": "prompt-eng",
    "releases": "release",
    "testing": "testgen",
}

# AGENTS.md carries no skill names, only "## When ..." headings (or, for a
# few skills, an inline mention). Map each canonical skill to a distinctive
# string that marks its coverage in the file.
AGENTS_MD_MARKERS = {
    "apply-working-process": "## Standard working process",
    "debug": "## When something fails (debugging)",
    "testgen": "## When writing tests",
    "deep-review": "## When reviewing code",
    "prove": "## Before claiming done",
    "sec-audit": "## When touching security-sensitive code",
    "perf": "## When optimizing",
    "ci-triage": "## When CI is red",
    "migrate": "## When upgrading or migrating",
    "api-design": "## When designing an interface",
    "frontend-design": "## When building or restyling a UI",
    "declutter": "## When simplifying / cleaning up",
    "incident": "## When production is down (incidents)",
    "postmortem": "the postmortem is blameless",
    "release": "## When releasing",
    "estimate": "## When estimating",
    "onboard": "## When the codebase is unfamiliar",
    "pr-workflow": "## When preparing a PR",
    "data-analysis": "## When analyzing data",
    "brainstorm": "## When brainstorming",
    "explain": "## When explaining",
    "prompt-eng": "## When writing prompts (LLM features)",
    "research-codebase": "## When researching how the codebase works",
    "handoff": "## Session continuity",
    "ste-writing": "## Prose style (all text you write)",
}


def present_stems(dir_path: Path, pattern: str, alias: dict = None) -> set:
    """Stems (or, for a SKILL.md match, the parent directory name) of every
    file under dir_path matching pattern, with alias applied if given."""
    present = set()
    if not dir_path.is_dir():
        return present
    for f in dir_path.glob(pattern):
        stem = f.parent.name if f.name == "SKILL.md" else f.stem
        present.add(alias.get(stem, stem) if alias else stem)
    return present


def agents_md_present(lib: Path, canonical: list) -> set:
    # Only the explicit marker map counts as coverage. A plain substring
    # search on the skill name gives false positives for common English
    # words the skill is named after ("write", "spec", "research"), so a
    # skill with no marker entry is reported missing, not guessed present.
    text = (lib / "ports" / "agents-md" / "AGENTS.md").read_text()
    lower = text.lower()
    present = set()
    for name in canonical:
        marker = AGENTS_MD_MARKERS.get(name)
        if marker and marker.lower() in lower:
            present.add(name)
    return present


def load_allowlist(lib: Path) -> set:
    allow_file = lib / "scripts" / "parity-allow.txt"
    entries = set()
    if not allow_file.is_file():
        return entries
    for line in allow_file.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if ":" not in line:
            continue
        surface, skill = line.split(":", 1)
        entries.add((surface.strip(), skill.strip()))
    return entries


def main() -> int:
    default_lib = Path(__file__).resolve().parent.parent
    lib = Path(sys.argv[1]) if len(sys.argv) > 1 else default_lib
    canonical = sorted(_lib.skill_names(lib, "skills"))
    if not canonical:
        print(f"FAIL: 0 canonical skills found under {lib / 'skills'} — wrong LIB_ROOT?")
        return 1
    allow = load_allowlist(lib)

    # surface name -> (dir, glob pattern, alias map or None)
    surface_globs = {
        "skills-local": (lib / "skills-local", "*/SKILL.md", None),
        "cursor": (lib / "ports" / "cursor", "*.mdc", CURSOR_ALIAS),
        "gemini": (lib / "ports" / "gemini" / "commands", "*.toml", None),
        "antigravity": (lib / "antigravity" / "workflows", "*.md", None),
    }
    surfaces = {
        surface: present_stems(dir_path, pattern, alias)
        for surface, (dir_path, pattern, alias) in surface_globs.items()
    }
    surfaces["agents-md"] = agents_md_present(lib, canonical)

    failed = False
    print(f"Canonical skills: {len(canonical)}")
    for surface, present in surfaces.items():
        missing = [s for s in canonical if s not in present]
        allowed_missing = [s for s in missing if (surface, s) in allow]
        real_missing = [s for s in missing if (surface, s) not in allow]
        if not missing:
            print(f"[{surface}] OK — all {len(canonical)} skills present")
            continue
        if allowed_missing:
            print(f"[{surface}] allowlisted gaps: {', '.join(allowed_missing)}")
        if real_missing:
            failed = True
            print(f"[{surface}] MISSING: {', '.join(real_missing)}")
        elif not allowed_missing:
            print(f"[{surface}] OK — all {len(canonical)} skills present")

    if failed:
        print("\nParity check FAILED — see MISSING lines above.")
        return 1
    print("\nParity check passed (allowlisted gaps, if any, are listed above).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
