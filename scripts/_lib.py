"""_lib.py — shared helpers for the scripts/*.py check scripts.

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
