#!/usr/bin/env python3
"""build-profile.py — generate the Claude Code profile from canonical skills.

skills/ stays spec-portable (Agent Skills spec keys only: name,
description, license, compatibility, metadata, allowed-tools). This
script reads scripts/profile-claude-code.yaml (a mapping of skill name to
extra Claude-Code-only frontmatter keys) and writes, for every canonical
skill under skills/, a copy at build/claude-code/skills/<name>/SKILL.md
whose frontmatter is the canonical frontmatter plus that skill's extra
keys (if any). references/ and scripts/ subdirectories under a skill's
canonical directory are copied alongside it unchanged.

Usage: python3 scripts/build-profile.py [LIB_ROOT] [--check]
  --check: write nothing; exit 1 if the existing build/claude-code/skills
           tree does not match what generation would produce (missing
           skills, extra skills, or any SKILL.md content mismatch).
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


def load_profile(lib: Path) -> dict:
    profile_path = lib / "scripts" / "profile-claude-code.yaml"
    if not profile_path.is_file():
        return {}
    data = yaml.safe_load(profile_path.read_text()) or {}
    if not isinstance(data, dict):
        raise ValueError(f"{profile_path}: expected a mapping at the top level")
    return data


def render_skill_md(canonical_path: Path, extra_keys: dict) -> str:
    """Return the generated SKILL.md text: canonical frontmatter plus
    extra_keys, followed by the canonical body unchanged."""
    text = canonical_path.read_text(encoding="utf-8")
    lines = text.splitlines(keepends=True)
    if not lines or lines[0].rstrip("\n\r") != "---":
        raise ValueError(f"{canonical_path}: missing frontmatter fence")
    end_idx = None
    for i in range(1, len(lines)):
        if lines[i].rstrip("\n\r") == "---":
            end_idx = i
            break
    if end_idx is None:
        raise ValueError(f"{canonical_path}: frontmatter fence never closes")

    frontmatter_text = "".join(lines[1:end_idx])
    data = yaml.safe_load(frontmatter_text) or {}
    if not isinstance(data, dict):
        raise ValueError(f"{canonical_path}: frontmatter is not a mapping")

    merged = dict(data)
    merged.update(extra_keys)

    # Preserve key order: canonical keys first (in their original order),
    # then any new keys the profile adds, for a stable, readable diff.
    ordered = {}
    for key in data:
        ordered[key] = merged[key]
    for key in extra_keys:
        if key not in ordered:
            ordered[key] = merged[key]

    new_frontmatter = yaml.safe_dump(
        ordered, default_flow_style=False, sort_keys=False, allow_unicode=True
    )
    body = "".join(lines[end_idx + 1 :])
    return f"---\n{new_frontmatter}---\n{body}"


def generate(lib: Path) -> dict:
    """Return {relative_path_under_build: content_or_None (None = directory
    marker not needed; binary/subdir files are copied directly, not
    returned here)} — SKILL.md contents only, keyed by skill name."""
    profile = load_profile(lib)
    canonical = _lib.skill_dirs(lib, "skills")
    result = {}
    for skill_dir in canonical:
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
    than a `skills` entry on the existing plugin.json — see PR description
    for the doc citation.
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
        " (context, argument-hint) generated from the portable library."
    )
    (manifest_dir / "plugin.json").write_text(json.dumps(manifest, indent=2) + "\n")

    for sub in ("agents", "hooks"):
        src = lib / sub
        dest = build_plugin_root / sub
        if dest.exists():
            shutil.rmtree(dest)
        if src.is_dir():
            shutil.copytree(src, dest)


def check_build(lib: Path, generated: dict) -> list:
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


def main() -> int:
    args = [a for a in sys.argv[1:] if a != "--check"]
    check_only = "--check" in sys.argv[1:]
    default_lib = Path(__file__).resolve().parent.parent
    lib = Path(args[0]) if args else default_lib

    canonical = _lib.skill_dirs(lib, "skills")
    if not canonical:
        print(f"FAIL: 0 canonical skills found under {lib / 'skills'} — wrong LIB_ROOT?")
        return 1

    generated = generate(lib)

    if check_only:
        errors = check_build(lib, generated)
        if errors:
            for e in errors:
                print(f"FAIL: {e}")
            print(f"\n{len(errors)} build-profile drift error(s).")
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
