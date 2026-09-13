#!/usr/bin/env python3
"""check-frontmatter.py — validate SKILL.md frontmatter across the library.

For every skills/**/SKILL.md and skills-local/**/SKILL.md, checks:
  - the file has YAML frontmatter (--- ... ---) at the top
  - its `name` matches the directory name
  - its `description` is present, non-empty, and under 1024 chars
  - it carries no key outside the Agent Skills spec set, unless the file
    is listed in scripts/frontmatter-allow.txt

Exits 1 if any file fails a check.

Uses PyYAML if available, else a minimal top-level-key parser (these
files only ever use flat string/bool keys).
"""
import sys
from pathlib import Path

SPEC_KEYS = {"name", "description", "license", "compatibility", "metadata", "allowed-tools"}
MAX_DESCRIPTION = 1024


def parse_frontmatter(text: str):
    if not text.startswith("---\n") and not text.startswith("---\r\n"):
        return None
    end = text.find("\n---", 4)
    if end == -1:
        return None
    block = text[4:end]
    try:
        import yaml  # type: ignore

        data = yaml.safe_load(block)
        return data if isinstance(data, dict) else None
    except ImportError:
        return _parse_flat(block)


def _parse_flat(block: str) -> dict:
    """Minimal parser for flat `key: value` frontmatter (no nesting)."""
    data: dict = {}
    key = None
    for line in block.splitlines():
        if not line.strip():
            continue
        if line[:1] in (" ", "\t") and key is not None:
            # continuation line — append to current key's value
            data[key] = f"{data[key]} {line.strip()}"
            continue
        if ":" not in line:
            continue
        k, _, v = line.partition(":")
        key = k.strip()
        data[key] = v.strip().strip('"').strip("'")
    return data


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
    text = path.read_text()
    data = parse_frontmatter(text)
    if data is None:
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

    if rel not in allow:
        extra_keys = set(data.keys()) - SPEC_KEYS
        if extra_keys:
            errors.append(
                f"{rel}: keys outside the Agent Skills spec: {', '.join(sorted(extra_keys))}"
            )

    return errors


def main() -> int:
    lib = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.cwd()
    allow = load_allowlist(lib)

    files = sorted(lib.glob("skills/*/SKILL.md")) + sorted(lib.glob("skills-local/*/SKILL.md"))
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

    print("All SKILL.md frontmatter valid.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
