"""Tests for the ways-of-working MCP server's pure logic.

Imports from `library`, not `server` — `library` carries the frontmatter
parser, skill discovery, and route() keyword matching with no dependency on
the `mcp` package, so these tests run without `mcp` installed.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import library  # noqa: E402


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


def test_discover_skills_count_and_names():
    names = {s.name for s in library.discover_skills()}
    assert len(names) == 34
    assert "demo-video" in names
    assert "plain-language" in names
    assert "ste-writing" in names


def test_instructions_list_every_discovered_skill():
    instructions = library.build_instructions()
    names = {s.name for s in library.discover_skills()}
    missing = [name for name in names if name not in instructions]
    assert not missing, f"instructions missing skills: {missing}"
