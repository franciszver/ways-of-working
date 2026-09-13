#!/usr/bin/env python3
"""build-profile.py — generate the committed Claude Code profile.

skills/ stays spec-portable (Agent Skills spec keys only: name,
description, license, compatibility, metadata, allowed-tools). This
script reads scripts/profile-claude-code.yaml (a mapping of skill name to
extra Claude-Code-only frontmatter keys) and writes, for every canonical
skill under skills/, a copy at build/claude-code/skills/<name>/SKILL.md
whose frontmatter is the canonical frontmatter plus that skill's extra
keys. references/ and scripts/ subdirectories under a skill's canonical
directory are copied alongside it unchanged. It also writes
build/claude-code/ as a standalone plugin root (its own
.claude-plugin/plugin.json, agents/, hooks/).

build/claude-code/ is committed, like the antigravity stubs and
hooks/plugin-hooks.json — this script is the generator, --check is the
drift gate CI runs, not a build step at install time.

Usage: python3 scripts/build-profile.py [LIB_ROOT] [--check]
  --check: write nothing; exit 1 if the committed build/claude-code/skills
           tree does not match what generation would produce, or if any
           generated SKILL.md fails the frontmatter contract (name == dir,
           non-empty description under 1024 chars, no keys outside the
           Agent Skills spec plus the allowed profile keys).
Requires PyYAML (exits 2 if missing).
"""
import json
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import _lib

try:
    import yaml  # type: ignore
except ImportError:
    print("FAIL: PyYAML is required (pip install pyyaml)", file=sys.stderr)
    raise SystemExit(2)

COPY_SUBDIRS = ("references", "scripts")

SPEC_KEYS = {"name", "description", "license", "compatibility", "metadata", "allowed-tools"}
MAX_DESCRIPTION = 1024

# Claude-Code-only frontmatter keys a profile entry may add. Anything else
# is rejected — see scripts/profile-claude-code.yaml's header comment for
# why context/fork isn't used yet.
ALLOWED_PROFILE_KEYS = {
    "context", "agent", "argument-hint", "disable-model-invocation",
    "user-invocable", "model", "effort",
}


def load_profile(lib: Path) -> dict:
    profile_path = lib / "scripts" / "profile-claude-code.yaml"
    if not profile_path.is_file():
        return {}
    data = yaml.safe_load(profile_path.read_text()) or {}
    if not isinstance(data, dict):
        raise ValueError(f"{profile_path}: expected a mapping at the top level")
    return data


def validate_profile(lib: Path, profile: dict) -> list:
    """Check scripts/profile-claude-code.yaml against the rules: every
    name must be a canonical skill, every extra key must be in
    ALLOWED_PROFILE_KEYS, and no extra key may already exist in that
    skill's canonical frontmatter."""
    errors = []
    canonical_dirs = {d.name: d for d in _lib.skill_dirs(lib, "skills")}

    for name, extra_keys in profile.items():
        if name not in canonical_dirs:
            errors.append(f"profile-claude-code.yaml: '{name}' is not a canonical skill")
            continue
        if not isinstance(extra_keys, dict):
            errors.append(f"profile-claude-code.yaml: '{name}' entry must be a mapping")
            continue

        bad_keys = set(extra_keys) - ALLOWED_PROFILE_KEYS
        if bad_keys:
            errors.append(
                f"profile-claude-code.yaml: '{name}' has keys outside the allowed"
                f" profile set: {', '.join(sorted(bad_keys))}"
                f" (allowed: {', '.join(sorted(ALLOWED_PROFILE_KEYS))})"
            )

        canonical_data = _lib.parse_frontmatter(canonical_dirs[name] / "SKILL.md")
        collisions = set(extra_keys) & set(canonical_data)
        if collisions:
            errors.append(
                f"profile-claude-code.yaml: '{name}' keys already present in its"
                f" canonical frontmatter: {', '.join(sorted(collisions))}"
            )

    return errors


def render_skill_md(canonical_path: Path, extra_keys: dict) -> str:
    """Return the generated SKILL.md text: canonical frontmatter plus
    extra_keys, followed by the canonical body unchanged."""
    frontmatter_text, body = _lib.split_frontmatter(canonical_path)
    data = yaml.safe_load(frontmatter_text) or {}
    if not isinstance(data, dict):
        raise ValueError(f"{canonical_path}: frontmatter is not a mapping")

    merged = dict(data)
    merged.update(extra_keys)  # dict order: canonical keys first, then new ones

    new_frontmatter = yaml.safe_dump(
        merged, default_flow_style=False, sort_keys=False, allow_unicode=True
    )
    return f"---\n{new_frontmatter}---\n{body}"


def generate(lib: Path, profile: dict) -> dict:
    """Return {skill_name: generated SKILL.md text}."""
    result = {}
    for skill_dir in _lib.skill_dirs(lib, "skills"):
        name = skill_dir.name
        extra_keys = profile.get(name, {})
        result[name] = render_skill_md(skill_dir / "SKILL.md", extra_keys)
    return result


def write_build(lib: Path, generated: dict) -> None:
    build_root = lib / "build" / "claude-code" / "skills"
    if build_root.exists():
        shutil.rmtree(build_root)
    build_root.mkdir(parents=True)

    canonical_by_name = {d.name: d for d in _lib.skill_dirs(lib, "skills")}
    for name, content in generated.items():
        dest_dir = build_root / name
        dest_dir.mkdir(parents=True, exist_ok=True)
        (dest_dir / "SKILL.md").write_text(content, encoding="utf-8")

        src_dir = canonical_by_name[name]
        for sub in COPY_SUBDIRS:
            src_sub = src_dir / sub
            if src_sub.is_dir():
                shutil.copytree(src_sub, dest_dir / sub)


def write_plugin_root(lib: Path) -> None:
    """Materialize build/claude-code/ as a standalone plugin root: its own
    .claude-plugin/plugin.json (a copy of the canonical one — plugin.json
    itself carries no non-spec keys, only skills/ needs the profile), plus
    agents/ and hooks/ copied verbatim so `claude plugin validate
    build/claude-code --strict` passes against a self-contained tree. A
    plugin's own ./skills is always scanned by default and cannot be
    swapped out via the manifest's `skills` field (that field only *adds*
    directories), so the enhanced profile needs its own plugin root rather
    than a `skills` entry on the existing plugin.json — see
    CONTRIBUTING.md for the doc citation.
    """
    build_plugin_root = lib / "build" / "claude-code"
    manifest_dir = build_plugin_root / ".claude-plugin"
    manifest_dir.mkdir(parents=True, exist_ok=True)

    canonical_manifest = json.loads((lib / ".claude-plugin" / "plugin.json").read_text())
    manifest = dict(canonical_manifest)
    manifest["name"] = f"{canonical_manifest['name']}-claude-code"
    manifest["description"] = (
        canonical_manifest["description"]
        + " This variant's skills/ carries Claude-Code-only frontmatter"
        " (argument-hint) generated from the portable library."
    )
    (manifest_dir / "plugin.json").write_text(json.dumps(manifest, indent=2) + "\n")

    for sub in ("agents", "hooks"):
        src = lib / sub
        dest = build_plugin_root / sub
        if dest.exists():
            shutil.rmtree(dest)
        if src.is_dir():
            shutil.copytree(src, dest)


def check_build_drift(lib: Path, generated: dict) -> list:
    build_root = lib / "build" / "claude-code" / "skills"
    errors = []
    if not build_root.is_dir():
        return [f"{build_root} does not exist — run scripts/build-profile.py first"]

    existing_names = {d.name for d in build_root.iterdir() if d.is_dir()}
    expected_names = set(generated)

    for missing in sorted(expected_names - existing_names):
        errors.append(f"missing generated skill: {missing}")
    for extra in sorted(existing_names - expected_names):
        errors.append(f"unexpected generated skill (not in canonical skills/): {extra}")

    for name in sorted(expected_names & existing_names):
        skill_md = build_root / name / "SKILL.md"
        if not skill_md.is_file():
            errors.append(f"{name}: build/claude-code/skills/{name}/SKILL.md missing")
            continue
        actual = skill_md.read_text(encoding="utf-8")
        if actual != generated[name]:
            errors.append(f"{name}: SKILL.md content is stale — re-run scripts/build-profile.py")

    return errors


def check_generated_frontmatter(lib: Path) -> list:
    """Frontmatter contract over the generated tree: name matches its
    directory, description is non-empty and under the limit, and no key
    falls outside the Agent Skills spec plus the allowed profile keys."""
    errors = []
    allowed_keys = SPEC_KEYS | ALLOWED_PROFILE_KEYS
    build_root = lib / "build" / "claude-code" / "skills"
    if not build_root.is_dir():
        return []  # reported by check_build_drift already

    for skill_dir in sorted(d for d in build_root.iterdir() if d.is_dir()):
        skill_md = skill_dir / "SKILL.md"
        if not skill_md.is_file():
            continue  # reported by check_build_drift already
        rel = skill_md.relative_to(lib)
        data = _lib.parse_frontmatter(skill_md)
        if not data:
            errors.append(f"{rel}: missing or malformed YAML frontmatter")
            continue

        name = data.get("name")
        if not name:
            errors.append(f"{rel}: no `name` key")
        elif name != skill_dir.name:
            errors.append(f"{rel}: name '{name}' does not match directory '{skill_dir.name}'")

        description = data.get("description")
        if not description or not str(description).strip():
            errors.append(f"{rel}: `description` is missing or empty")
        elif len(str(description)) > MAX_DESCRIPTION:
            errors.append(
                f"{rel}: `description` is {len(str(description))} chars,"
                f" over the {MAX_DESCRIPTION} limit"
            )

        extra_keys = set(data.keys()) - allowed_keys
        if extra_keys:
            errors.append(
                f"{rel}: keys outside the spec + profile allowlist: {', '.join(sorted(extra_keys))}"
            )

    return errors


def main() -> int:
    args = [a for a in sys.argv[1:] if a != "--check"]
    check_only = "--check" in sys.argv[1:]
    default_lib = Path(__file__).resolve().parent.parent
    lib = Path(args[0]) if args else default_lib

    canonical = _lib.skill_dirs(lib, "skills")
    if not canonical:
        print(f"FAIL: 0 canonical skills found under {lib / 'skills'} — wrong LIB_ROOT?")
        return 1

    profile = load_profile(lib)
    profile_errors = validate_profile(lib, profile)
    if profile_errors:
        for e in profile_errors:
            print(f"FAIL: {e}")
        print(f"\n{len(profile_errors)} profile-claude-code.yaml error(s).")
        return 1

    generated = generate(lib, profile)

    if check_only:
        errors = check_build_drift(lib, generated)
        errors += check_generated_frontmatter(lib)
        if errors:
            for e in errors:
                print(f"FAIL: {e}")
            print(f"\n{len(errors)} build-profile error(s).")
            return 1
        print(f"build/claude-code/skills/ matches {len(generated)} canonical skills. No drift.")
        return 0

    write_build(lib, generated)
    write_plugin_root(lib)
    print(f"Generated build/claude-code/skills/ from {len(generated)} canonical skills.")
    print("Generated build/claude-code/ plugin root (plugin.json, agents/, hooks/).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
