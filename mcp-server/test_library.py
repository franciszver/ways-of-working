"""Tests for the ways-of-working MCP server's pure logic.

Imports `library`, not `server` — `library` carries skill discovery and
route() keyword matching with no dependency on the `mcp` package, so these
tests run without `mcp` installed. See test_server.py for the mcp-dependent
server tests.
"""

from __future__ import annotations

import importlib
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(REPO_ROOT / "scripts"))

import _lib  # noqa: E402
import library  # noqa: E402


@pytest.fixture(autouse=True)
def hermetic_library(monkeypatch):
    """Unset WAYS_OF_WORKING_LIBRARY and reload `library`, so tests always
    see this repo's own skills regardless of the calling environment."""
    monkeypatch.delenv("WAYS_OF_WORKING_LIBRARY", raising=False)
    importlib.reload(library)
    yield
    importlib.reload(library)


def test_library_does_not_import_mcp():
    """Importing `library` alone must not pull in `mcp`.

    Run in a fresh subprocess: pytest's collection phase imports every test
    module up front, including test_server.py's `import server` (which does
    import `mcp`) — checking sys.modules in-process here would depend on
    test collection order rather than on library.py's own imports.
    """
    result = subprocess.run(
        [
            sys.executable,
            "-c",
            f"import sys; sys.path.insert(0, {str(Path(__file__).resolve().parent)!r}); "
            "import library; assert 'mcp' not in sys.modules",
        ],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stderr


def test_route_prove_has_no_pr_hint():
    assert "pr-workflow" not in library.route("prove the fix works")


def test_route_open_pr_has_pr_hint():
    assert "pr-workflow" in library.route("open a PR for this branch")


def test_route_download_has_no_incident_hint():
    assert "production incident" not in library.route("download the dataset")


def test_route_site_is_down_has_incident_hint():
    assert "incident" in library.route("the site is down")


def test_route_cite_has_no_ci_triage_hint():
    assert "ci-triage" not in library.route("cite the source")


def test_route_ci_is_red_has_ci_triage_hint():
    assert "ci-triage" in library.route("CI is red")


def test_route_uint8_has_no_frontend_design_hint():
    assert "frontend-design" not in library.route("uint8 overflow bug")


def test_route_downtime_has_incident_hint():
    assert "incident" in library.route("20 minutes of downtime")


def test_route_redesign_uis_has_frontend_design_hint():
    assert "frontend-design" in library.route("redesign our UIs")


def test_discover_skills_matches_disk():
    names = {s.name for s in library.discover_skills()}
    assert names == _lib.skill_names(REPO_ROOT, "skills")
    assert "demo-video" in names
    assert "plain-language" in names
    assert "ste-writing" in names


def test_instructions_list_every_discovered_skill():
    instructions = library.build_instructions()
    names = {s.name for s in library.discover_skills()}
    missing = [name for name in names if name not in instructions]
    assert not missing, f"instructions missing skills: {missing}"


def test_every_canonical_skill_has_a_route_hint():
    all_hint_text = " ".join(hint for _, hint in library._ROUTE_HINT_SOURCE)
    names = _lib.skill_names(REPO_ROOT, "skills")
    missing = [name for name in names if name not in all_hint_text]
    assert not missing, f"no route hint mentions: {missing}"
