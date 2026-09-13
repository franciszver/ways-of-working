#!/usr/bin/env python3
"""check-agents.py — validate agents/*.md frontmatter across the library.

For every agents/*.md, checks:
  - the file has YAML frontmatter with a non-empty `name` and `description`
  - `code-reviewer` and `verifier` declare `disallowedTools` containing
    Edit, Write, and NotebookEdit
  - every agent declares a `skills:` list, and every listed skill exists
    as a directory under skills/
  - the file body (everything after the closing frontmatter fence) is at
    most 40 lines — agents preload doctrine via `skills:` instead of
    restating it in the body

Exits 1 if any file fails a check. Requires PyYAML (exits 2 if missing).
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

REQUIRED_DISALLOWED = {"Edit", "Write", "NotebookEdit"}
AGENTS_REQUIRING_DISALLOWED = {"code-reviewer", "verifier"}
MAX_BODY_LINES = 40


def body_line_count(path: Path) -> int:
    """Count lines in the file after the closing frontmatter fence."""
    lines = path.read_text(encoding="utf-8").splitlines()
    if not lines or lines[0].strip() != "---":
        return len(lines)
    for i, line in enumerate(lines[1:], start=1):
        if line.strip() == "---":
            body = lines[i + 1 :]
            # Drop leading/trailing blank lines — they're not content.
            while body and not body[0].strip():
                body.pop(0)
            while body and not body[-1].strip():
                body.pop()
            return len(body)
    return len(lines)


def as_list(value) -> list:
    if value is None:
        return []
    if isinstance(value, str):
        return [v.strip() for v in value.split(",") if v.strip()]
    if isinstance(value, list):
        return value
    return []


def check_file(path: Path, lib: Path, skill_names: set) -> list:
    errors = []
    rel = str(path.relative_to(lib))
    data = _lib.parse_frontmatter(path)
    if not data:
        return [f"{rel}: missing or malformed YAML frontmatter"]

    name = data.get("name")
    if not name or not str(name).strip():
        errors.append(f"{rel}: no `name` key")

    description = data.get("description")
    if not description or not str(description).strip():
        errors.append(f"{rel}: `description` is missing or empty")

    agent_name = name or path.stem
    if agent_name in AGENTS_REQUIRING_DISALLOWED:
        disallowed = set(as_list(data.get("disallowedTools")))
        missing = REQUIRED_DISALLOWED - disallowed
        if missing:
            errors.append(
                f"{rel}: `disallowedTools` missing {', '.join(sorted(missing))} "
                f"(required for {agent_name})"
            )

    skills = data.get("skills")
    skills_list = as_list(skills)
    if not skills_list:
        errors.append(f"{rel}: no `skills:` list — agents preload doctrine via skills")
    else:
        for s in skills_list:
            if s not in skill_names:
                errors.append(f"{rel}: `skills:` entry '{s}' has no skills/{s}/ directory")

    lines = body_line_count(path)
    if lines > MAX_BODY_LINES:
        errors.append(f"{rel}: body is {lines} lines, over the {MAX_BODY_LINES}-line limit")

    return errors


def main() -> int:
    default_lib = Path(__file__).resolve().parent.parent
    lib = Path(sys.argv[1]) if len(sys.argv) > 1 else default_lib

    agents_dir = lib / "agents"
    files = sorted(agents_dir.glob("*.md")) if agents_dir.is_dir() else []
    if not files:
        print(f"FAIL: 0 agent files found under {agents_dir} — wrong LIB_ROOT?")
        return 1

    skill_names = _lib.skill_names(lib, "skills")

    all_errors = []
    for f in files:
        all_errors.extend(check_file(f, lib, skill_names))

    print(f"Checked {len(files)} agent files.")
    if all_errors:
        for e in all_errors:
            print(f"FAIL: {e}")
        print(f"\n{len(all_errors)} agent frontmatter error(s).")
        return 1

    print("All agent frontmatter valid.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
