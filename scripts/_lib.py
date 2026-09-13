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


def split_frontmatter(path: Path) -> tuple:
    """Split a SKILL.md-style file into (frontmatter_text, body_text).

    frontmatter_text is the raw text between the opening and closing `---`
    fences (not yet YAML-parsed); body_text is everything after the
    closing fence. Raises ValueError if the file has no opening fence or
    the fence never closes.
    """
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines(keepends=True)
    if not lines or lines[0].rstrip("\n\r") != "---":
        raise ValueError(f"{path}: missing frontmatter fence")
    end_idx = None
    for i in range(1, len(lines)):
        if lines[i].rstrip("\n\r") == "---":
            end_idx = i
            break
    if end_idx is None:
        raise ValueError(f"{path}: frontmatter fence never closes")
    frontmatter_text = "".join(lines[1:end_idx])
    body_text = "".join(lines[end_idx + 1 :])
    return frontmatter_text, body_text


def parse_frontmatter(path: Path) -> dict:
    """Parse a SKILL.md-style file's YAML frontmatter.

    Returns {} if the file has no frontmatter, the fence never closes, or
    the parsed YAML is not a mapping. Requires PyYAML — imported lazily so
    skill_dirs/skill_names stay usable without it.
    """
    import yaml

    try:
        frontmatter_text, _ = split_frontmatter(path)
    except ValueError:
        return {}
    try:
        data = yaml.safe_load(frontmatter_text)
    except yaml.YAMLError:
        return {}
    return data if isinstance(data, dict) else {}
