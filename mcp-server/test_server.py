"""MCP-dependent tests for the ways-of-working server.

Requires the `mcp` package — skipped automatically when it isn't installed.
See test_library.py for the mcp-independent tests of the pure logic.
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

pytest.importorskip("mcp")

sys.path.insert(0, str(Path(__file__).resolve().parent))

import server  # noqa: E402


def test_prompt_count_matches_canonical_skill_count():
    prompts = server.mcp._prompt_manager.list_prompts()
    assert len(prompts) == len(server._CANONICAL_SKILLS)


def test_instructions_contain_every_canonical_skill_name():
    names = {s.name for s in server._CANONICAL_SKILLS}
    missing = [name for name in names if name not in server.mcp.instructions]
    assert not missing, f"instructions missing skills: {missing}"
