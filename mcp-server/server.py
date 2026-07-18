"""fable-quality MCP server.

Exposes the fable-quality-library to any MCP-capable agent:
- tools: list_skills, get_skill, get_playbook, route
- prompts: one per canonical skill (invoking a prompt injects the skill text)

Stdio transport (the default). Library root resolves from the
FABLE_QUALITY_LIBRARY env var, falling back to this file's parent repo.

Authored as part of the library's plumbing phase and NOT yet executed —
see README.md for the two-minute smoke test before first use.
"""

from __future__ import annotations

import os
import re
from dataclasses import dataclass
from pathlib import Path

from mcp.server.fastmcp import FastMCP
from mcp.server.fastmcp.prompts import Prompt

LIBRARY_ROOT = Path(
    os.environ.get("FABLE_QUALITY_LIBRARY", Path(__file__).resolve().parent.parent)
)

PROFILES = {
    "canonical": LIBRARY_ROOT / "skills",
    "local": LIBRARY_ROOT / "skills-local",
}
PLAYBOOK_DIR = LIBRARY_ROOT / "playbooks"

mcp = FastMCP(
    "fable-quality",
    instructions=(
        "Quality-process library: 31 judgment-dense skills covering software engineering, "
        "ops/incidents, codebase navigation, and non-engineering work. "
        "Core: debug, deep-review, prove, spec, architect, breakdown, refactor, testgen, research, write, handoff, lean-max-effort, apply-working-process. "
        "SE gaps: sec-audit, perf, ci-triage, migrate, api-design, frontend-design, declutter. "
        "Ops: incident, postmortem, release. "
        "Navigation: onboard, estimate, pr-workflow. "
        "Non-engineering: data-analysis, brainstorm, explain, prompt-eng, research-codebase. "
        "Also: model-routing and handoff playbooks. "
        "Call list_skills to see the full catalog; get_skill/get_playbook to load one; "
        "route for model-selection guidance. Prompts named after skills inject the skill text "
        "plus your task."
    ),
)


@dataclass
class Skill:
    name: str
    description: str
    profile: str
    path: Path

    def body(self) -> str:
        return self.path.read_text(encoding="utf-8")


def _parse_frontmatter(text: str) -> dict[str, str]:
    """Minimal frontmatter parser: single-line `key: value` pairs between --- fences.

    Deliberately not YAML — the library's frontmatter is flat by convention, and
    this keeps the server dependency-light.
    """
    fields: dict[str, str] = {}
    if not text.startswith("---"):
        return fields
    match = re.match(r"^---\n(.*?)\n---\n", text, re.DOTALL)
    if not match:
        return fields
    for line in match.group(1).splitlines():
        if ":" not in line:
            continue
        key, _, value = line.partition(":")
        fields[key.strip()] = value.strip().strip("\"'")
    return fields


def discover_skills() -> list[Skill]:
    skills: list[Skill] = []
    for profile, root in PROFILES.items():
        if not root.is_dir():
            continue
        for skill_md in sorted(root.glob("*/SKILL.md")):
            fm = _parse_frontmatter(skill_md.read_text(encoding="utf-8"))
            skills.append(
                Skill(
                    name=fm.get("name", skill_md.parent.name),
                    description=fm.get("description", ""),
                    profile=profile,
                    path=skill_md,
                )
            )
    return skills


def _find_skill(name: str, profile: str) -> Skill | None:
    matches = [s for s in discover_skills() if s.name == name]
    if not matches:
        return None
    for s in matches:
        if s.profile == profile:
            return s
    return matches[0]


@mcp.tool()
def list_skills() -> str:
    """List every available skill: name, profile (canonical = frontier models,
    local = small local models), and what it does."""
    lines = []
    for s in discover_skills():
        desc = s.description.split(". ")[0].rstrip(".")
        lines.append(f"- {s.name} [{s.profile}] — {desc}")
    if not lines:
        return f"No skills found under {LIBRARY_ROOT} — check FABLE_QUALITY_LIBRARY."
    return "\n".join(lines)


@mcp.tool()
def get_skill(name: str, profile: str = "canonical") -> str:
    """Fetch a skill's full text. Follow it as your working protocol for the task
    at hand. profile: 'canonical' (frontier models — token-lean, judgment-dense)
    or 'local' (small local models — imperative, verification-heavy)."""
    skill = _find_skill(name, profile)
    if skill is None:
        available = ", ".join(sorted({s.name for s in discover_skills()}))
        return f"Unknown skill '{name}'. Available: {available}"
    return skill.body()


def _read_playbook(name: str) -> str:
    if not PLAYBOOK_DIR.is_dir():
        return f"No playbooks directory at {PLAYBOOK_DIR}."
    books = {p.stem.lower(): p for p in sorted(PLAYBOOK_DIR.glob("*.md"))}
    if not name:
        return "\n".join(f"- {stem}" for stem in books)
    book = books.get(name.lower())
    if book is None:
        return f"Unknown playbook '{name}'. Available: {', '.join(books)}"
    return book.read_text(encoding="utf-8")


@mcp.tool()
def get_playbook(name: str = "") -> str:
    """Fetch a playbook. 'routing' = which model/tier for which task;
    'handoff' = cross-tool session-continuity convention. Empty name lists them."""
    return _read_playbook(name)


# Deterministic first-pass hints; the real judgment lives in ROUTING.md, which
# route() returns for the caller to apply. Honest heuristic, not fake intelligence.
_ROUTE_HINTS: list[tuple[str, str]] = [
    (
        r"\b(architect|design|schema|data model|api design|migration plan)\b",
        "signals architecture/one-way-door work → highest available tier",
    ),
    (
        r"\b(frontend|ui|ux|css|layout|responsive|component|styling|stylesheet|design.?system|theme|accessib)\w*\b",
        "signals UI/visual design work → frontend-design skill, commit to tokens before components",
    ),
    (
        r"\b((working|operating) (process|model)|how (I|we) like to work|session start|project kickoff|new project setup)\b",
        "signals session/project setup → apply-working-process skill, adopt the standard process before task work",
    ),
    (
        r"\b(race|deadlock|heisenbug|flaky|intermittent|concurren)\w*\b",
        "signals gnarly debugging → high tier",
    ),
    (
        # "auth" variants deliberately exclude author/authoring
        r"\b(security|payment|billing|secret)\w*\b"
        r"|\bauth(n|z|entication|orization|enticate|orize[sd]?)?\b",
        "signals high-stakes review → high tier with fresh context (skill: sec-audit)",
    ),
    (
        r"\b(incident|outage|down|degraded|pager|on.?call|alert)\w*\b",
        "signals production incident → use incident skill, mitigate before diagnosing",
    ),
    (
        r"\b(postmortem|retrospective|blameless|root.?cause)\w*\b",
        "signals incident retrospective → postmortem skill",
    ),
    (
        r"\b(deploy|release|rollout|canary|feature.?flag|publish)\w*\b",
        "signals release work → release skill, verify + stage + watch",
    ),
    (
        r"\b(onboard|unfamiliar|new.?repo|picking.?up|orient)\w*\b",
        "signals codebase orientation → onboard skill",
    ),
    (
        r"\b(estimat|how.?long|how.?big|scope|effort|deadline)\w*\b",
        "signals estimation → estimate skill, deliver a range not a number",
    ),
    (
        r"\b(pull.?request|PR|branch|commit|code.?review.?workflow)\w*\b",
        "signals PR prep/review work → pr-workflow skill",
    ),
    (
        r"\b(optim|slow|latency|throughput|memory.?leak|profile|bottleneck)\w*\b",
        "signals performance work → perf skill, profile before touching code",
    ),
    (
        r"\b(CI|pipeline|build.?red|build.?fail|flak)\w*\b",
        "signals broken build → ci-triage skill",
    ),
    (
        r"\b(upgrad|migrat|deprecat|breaking.?change|data.?migration|schema.?change)\w*\b",
        "signals migration/upgrade work → migrate skill",
    ),
    (
        r"\b(simplif|clean.?up|declutter|dead.?code|unused|remove.?boilerplate)\w*\b",
        "signals cleanup pass → declutter skill (behavior-preserving only)",
    ),
    (
        r"\b(dataset|metric|dashboard|experiment|A/B|analyze.?data|SQL.?query)\w*\b",
        "signals data analysis work → data-analysis skill",
    ),
    (
        r"\b(brainstorm|ideation|options|alternative|stuck|generate.?ideas?)\w*\b",
        "signals ideation → brainstorm skill, generate wide before judging",
    ),
    (
        r"\b(prompt.?engineer|system.?prompt|LLM.?feature|eval.?set)\w*\b",
        "signals prompt engineering → prompt-eng skill",
    ),
    (
        r"\b(how.?does.+work|where.+live|research.+codebase|document.+behavior)\w*\b",
        "signals codebase research → research-codebase skill, documentarian stance",
    ),
    (
        r"\b(rename|boilerplate|scaffold|convert|reformat|bulk|batch)\w*\b",
        "signals mechanical work → Haiku/local tier",
    ),
    (
        r"\b(summar|commit message|changelog|docstring)\w*\b",
        "signals light text work → Haiku tier",
    ),
]


@mcp.tool()
def route(task_description: str) -> str:
    """Recommend which model tier should handle a task. Returns keyword-based
    first-pass hints plus the full ROUTING playbook; apply the playbook's
    principles — the hints are only a starting point."""
    hints = [
        hint
        for pattern, hint in _ROUTE_HINTS
        if re.search(pattern, task_description, re.IGNORECASE)
    ]
    hint_text = (
        "Keyword hints for this task:\n" + "\n".join(f"- {h}" for h in hints)
        if hints
        else "No keyword hints matched — apply the playbook's principles directly."
    )
    playbook = _read_playbook("routing")
    return (
        f"{hint_text}\n\n"
        "Apply the routing playbook below (principles beat keywords; "
        "route by cost-of-being-wrong, not difficulty):\n\n"
        f"{playbook}"
    )


def _register_skill_prompts() -> None:
    """One MCP prompt per canonical skill: /<name> injects the skill + the task."""
    for skill in discover_skills():
        if skill.profile != "canonical":
            continue

        def make_fn(s: Skill):
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


_register_skill_prompts()


def main() -> None:
    mcp.run()


if __name__ == "__main__":
    main()
