"""_lib.py — shared helpers for the scripts/*.py check scripts and for
mcp-server/library.py.

Hyphenated filenames (check-frontmatter.py, check-counts.py) cannot import
this module by name directly; each does:

    import sys
    from pathlib import Path
    sys.path.insert(0, str(Path(__file__).parent))
    import _lib
"""
from pathlib import Path


def skill_dirs(lib: Path, subdir: str) -> list:
    """Sorted list of dirs under lib/subdir that contain a SKILL.md."""
    root = lib / subdir
    if not root.is_dir():
        return []
    return sorted(d for d in root.iterdir() if d.is_dir() and (d / "SKILL.md").is_file())


def skill_names(lib: Path, subdir: str) -> set:
    """Set of skill directory names under lib/subdir that contain a SKILL.md."""
    return {d.name for d in skill_dirs(lib, subdir)}


def parse_frontmatter(path: Path) -> dict:
    """Parse a SKILL.md-style file's YAML frontmatter.

    Reads only up to the closing `---` fence, not the whole file body.
    Returns {} if the file has no frontmatter, the fence never closes, or
    the parsed YAML is not a mapping. Requires PyYAML — imported lazily so
    skill_dirs/skill_names stay usable without it.
    """
    import yaml

    lines: list[str] = []
    with path.open(encoding="utf-8") as f:
        first = f.readline()
        if first.rstrip("\n\r") != "---":
            return {}
        for line in f:
            if line.rstrip("\n\r") == "---":
                break
            lines.append(line)
        else:
            return {}
    try:
        data = yaml.safe_load("".join(lines))
    except yaml.YAMLError:
        return {}
    return data if isinstance(data, dict) else {}
