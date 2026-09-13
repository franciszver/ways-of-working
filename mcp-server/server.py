"""ways-of-working MCP server.

Exposes the ways-of-working library to any MCP-capable agent:
- tools: list_skills, get_skill, get_playbook, route
- prompts: one per canonical skill (invoking a prompt injects the skill text)

Stdio transport (the default; see README.md to switch to streamable-http).
Library root resolves from the WAYS_OF_WORKING_LIBRARY env var, falling back
to this file's parent repo.

The pure logic (skill discovery, route hints) lives in library.py, which has
no dependency on the `mcp` package — see test_library.py. Frontmatter
parsing is shared with scripts/_lib.py, the repo's SKILL.md checks.
"""

from __future__ import annotations

from mcp.server.fastmcp import FastMCP
from mcp.server.fastmcp.prompts import Prompt

import library

_CANONICAL_SKILLS = library.discover_skills()

mcp = FastMCP("ways-of-working", instructions=library.build_instructions(_CANONICAL_SKILLS))


@mcp.tool()
def list_skills() -> str:
    """List every available skill: name, profile (canonical = frontier models,
    local = small local models), and what it does."""
    return library.list_skills_text()


@mcp.tool()
def get_skill(name: str, profile: str = "canonical") -> str:
    """Fetch a skill's full text. Follow it as your working protocol for the task
    at hand. profile: 'canonical' (frontier models — token-lean, judgment-dense)
    or 'local' (small local models — imperative, verification-heavy)."""
    return library.get_skill_text(name, profile)


@mcp.tool()
def get_playbook(name: str = "") -> str:
    """Fetch a playbook. 'routing' = which model/tier for which task;
    'handoff' = cross-tool session-continuity convention. Empty name lists them."""
    return library.read_playbook(name)


@mcp.tool()
def route(task_description: str) -> str:
    """Recommend which model tier should handle a task. Returns keyword-based
    first-pass hints plus the full ROUTING playbook; apply the playbook's
    principles — the hints are only a starting point."""
    return library.route(task_description)


def _register_skill_prompts(skills: list[library.Skill]) -> None:
    """One MCP prompt per canonical skill: /<name> injects the skill + the task."""
    for skill in skills:
        def make_fn(s: library.Skill):
            def prompt_fn(task: str = "") -> str:
                header = f"Follow this protocol for the task.\n\n{s.body()}"
                return f"{header}\n\n---\n\nTask: {task}" if task else header

            prompt_fn.__name__ = s.name.replace("-", "_")
            prompt_fn.__doc__ = s.description
            return prompt_fn

        mcp.add_prompt(
            Prompt.from_function(
                make_fn(skill), name=skill.name, description=skill.description
            )
        )


_register_skill_prompts(_CANONICAL_SKILLS)


def main() -> None:
    mcp.run()


if __name__ == "__main__":
    main()
