#!/usr/bin/env python3
"""check-frontmatter.py — validate SKILL.md frontmatter across the library.

For every skills/**/SKILL.md and skills-local/**/SKILL.md, checks:
  - the file has YAML frontmatter (--- ... ---) at the top
  - its `name` matches the directory name
  - its `description` is present, non-empty, and under 1024 chars
  - it carries no key outside the Agent Skills spec set, unless the file
    is listed in scripts/frontmatter-allow.txt
  - its `description` reads as a third-person capability statement, not an
    imperative instruction: its opening word ends in "s" (a third-person
    verb) or is a deliberately allowlisted non-verb opener (see
    NON_VERB_OPENERS below — extend it when a new description legitimately
    opens with a noun/adjective), does not say the skill is needed "at the
    start/beginning of any/every/each session/task", does not name a model,
    and stays under 1024 chars

Exits 1 if any file fails a check. Requires PyYAML (exits 2 if missing).
"""
import importlib.util
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import _lib


def _load_build_profile():
    """Import scripts/build-profile.py by path (hyphenated filename)."""
    path = Path(__file__).parent / "build-profile.py"
    spec = importlib.util.spec_from_file_location("build_profile", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

try:
    import yaml  # type: ignore
except ImportError:
    print("FAIL: PyYAML is required (pip install pyyaml)", file=sys.stderr)
    raise SystemExit(2)

SPEC_KEYS = {"name", "description", "license", "compatibility", "metadata", "allowed-tools"}
MAX_DESCRIPTION = 1024

# A description opener is either a third-person verb ("Designs …", "Runs …"
# — the common case, always ending in "s") or one of these non-verb openers
# ("Structured ideation …", "Security review …"). Derived by reading every
# current canonical and skills-local description's opening word. When a new
# description legitimately opens with a different non-verb word (an
# adjective or noun heading a noun phrase), add it here deliberately —
# that's the intended way to extend this allowlist, not a workaround.
NON_VERB_OPENERS = {
    "Adversarial", "Audience", "Behavior-preserving", "Blameless",
    "Branch-to-merge", "Calibrated", "Cleanup-only", "Documentarian",
    "Explicit", "Hypothesis-driven", "Mandatory", "Measurement-driven",
    "Performance", "Production", "Security", "Structured", "Triangulated",
}

# "Always on" phrasing belongs in claude-md/, not in a skill description.
ALWAYS_ON_RE = re.compile(
    r"\b(start|beginning) of (any|every|each)\b.{0,25}?(session|task)",
    re.IGNORECASE,
)

# Model names don't belong in a description (the skill must work under any
# model). The alternation is case-insensitive so it also catches lowercase
# mentions; the "Claude" branch stays case-sensitive and outside that flag
# so it doesn't false-positive on "claude-code-router". "Claude" alone is
# allowed when naming the product "Claude Code".
MODEL_NAME_RE = re.compile(
    r"\b(?i:sonnet|opus|haiku|gpt|gemini)\b|\bClaude\b(?!\s+Code)"
)


def check_description_style(description: str, rel: str) -> list:
    errors = []
    text = str(description).strip()
    first_word = text.split(None, 1)[0].rstrip(".,;:") if text else ""
    if first_word and not first_word.endswith("s") and first_word not in NON_VERB_OPENERS:
        errors.append(
            f"{rel}: description opens with '{first_word}', which reads as "
            "an imperative instruction — use third person (e.g. 'Designs "
            "…'), or add it to NON_VERB_OPENERS if it heads a noun phrase"
        )
    if ALWAYS_ON_RE.search(text):
        errors.append(
            f"{rel}: description claims to be needed \"at the start of any "
            "session/task\" — move always-on framing to claude-md/, keep "
            "task-shaped triggers here"
        )
    model_match = MODEL_NAME_RE.search(text)
    if model_match:
        errors.append(f"{rel}: description names a model ('{model_match.group(0)}')")
    return errors


def load_allowlist(lib: Path) -> dict:
    """scripts/frontmatter-allow.txt: one relative path per line, optional
    trailing '# comment'. Returns {relpath: comment}."""
    allow_file = lib / "scripts" / "frontmatter-allow.txt"
    entries: dict = {}
    if not allow_file.is_file():
        return entries
    for line in allow_file.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        path_part, _, comment = line.partition("#")
        entries[path_part.strip()] = comment.strip()
    return entries


def check_file(path: Path, lib: Path, allow: dict) -> list:
    errors = []
    rel = str(path.relative_to(lib))
    data = _lib.parse_frontmatter(path)
    if not data:
        return [f"{rel}: missing or malformed YAML frontmatter"]

    dirname = path.parent.name
    name = data.get("name")
    if not name:
        errors.append(f"{rel}: no `name` key")
    elif name != dirname:
        errors.append(f"{rel}: name '{name}' does not match directory '{dirname}'")

    description = data.get("description")
    if not description or not str(description).strip():
        errors.append(f"{rel}: `description` is missing or empty")
    elif len(str(description)) > MAX_DESCRIPTION:
        errors.append(
            f"{rel}: `description` is {len(str(description))} chars, over the {MAX_DESCRIPTION} limit"
        )
    else:
        errors.extend(check_description_style(description, rel))

    if rel not in allow:
        extra_keys = set(data.keys()) - SPEC_KEYS
        if extra_keys:
            errors.append(
                f"{rel}: keys outside the Agent Skills spec: {', '.join(sorted(extra_keys))}"
            )

    return errors


def main() -> int:
    default_lib = Path(__file__).resolve().parent.parent
    lib = Path(sys.argv[1]) if len(sys.argv) > 1 else default_lib
    allow = load_allowlist(lib)

    canonical = _lib.skill_dirs(lib, "skills")
    if not canonical:
        print(f"FAIL: 0 canonical skills found under {lib / 'skills'} — wrong LIB_ROOT?")
        return 1

    files = [d / "SKILL.md" for d in canonical]
    files += [d / "SKILL.md" for d in _lib.skill_dirs(lib, "skills-local")]
    all_errors = []
    for f in files:
        all_errors.extend(check_file(f, lib, allow))

    print(f"Checked {len(files)} SKILL.md files.")
    if allow:
        print(f"Allowlisted files (non-spec keys accepted): {', '.join(sorted(allow))}")
    if all_errors:
        for e in all_errors:
            print(f"FAIL: {e}")
        print(f"\n{len(all_errors)} frontmatter error(s).")
        return 1

    build_profile = _load_build_profile()
    generated = build_profile.generate(lib)
    profile_errors = build_profile.check_build(lib, generated)
    if profile_errors:
        for e in profile_errors:
            print(f"FAIL: build/claude-code profile: {e}")
        print(f"\n{len(profile_errors)} build-profile error(s).")
        return 1
    print(f"build/claude-code/skills/ matches {len(generated)} canonical skills.")

    print("All SKILL.md frontmatter valid.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
