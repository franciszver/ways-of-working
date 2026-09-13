#!/usr/bin/env python3
"""Parity check: canonical skill names (skills/*/SKILL.md) vs every port.

Called by scripts/check-parity.sh. Not meant to run standalone outside a
ways-of-working checkout.
"""
import sys
from pathlib import Path

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


def canonical_skills(lib: Path) -> list[str]:
    names = []
    for d in (lib / "skills").iterdir():
        if d.is_dir() and (d / "SKILL.md").is_file():
            names.append(d.name)
    return sorted(names)


def skills_local_present(lib: Path) -> set[str]:
    present = set()
    for d in (lib / "skills-local").iterdir():
        if d.is_dir() and (d / "SKILL.md").is_file():
            present.add(d.name)
    return present


def cursor_present(lib: Path) -> set[str]:
    present = set()
    for f in (lib / "ports" / "cursor").glob("*.mdc"):
        stem = f.stem
        present.add(CURSOR_ALIAS.get(stem, stem))
    return present


def gemini_present(lib: Path) -> set[str]:
    return {f.stem for f in (lib / "ports" / "gemini" / "commands").glob("*.toml")}


def antigravity_present(lib: Path) -> set[str]:
    return {f.stem for f in (lib / "antigravity" / "workflows").glob("*.md")}


def agents_md_present(lib: Path, canonical: list[str]) -> set[str]:
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


def load_allowlist(lib: Path) -> set[tuple[str, str]]:
    allow_file = lib / "scripts" / "parity-allow.txt"
    entries: set[tuple[str, str]] = set()
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
    lib = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.cwd()
    canonical = canonical_skills(lib)
    allow = load_allowlist(lib)

    surfaces = {
        "skills-local": skills_local_present(lib),
        "cursor": cursor_present(lib),
        "gemini": gemini_present(lib),
        "antigravity": antigravity_present(lib),
        "agents-md": agents_md_present(lib, canonical),
    }

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
