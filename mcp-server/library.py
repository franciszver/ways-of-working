"""Pure logic for the ways-of-working MCP server.

No dependency on the `mcp` package. server.py wraps these functions as MCP
tools; this module stays importable and testable without `mcp` installed.
"""

from __future__ import annotations

import os
import re
from dataclasses import dataclass
from pathlib import Path

LIBRARY_ROOT = Path(
    os.environ.get("WAYS_OF_WORKING_LIBRARY", Path(__file__).resolve().parent.parent)
)

PROFILES = {
    "canonical": LIBRARY_ROOT / "skills",
    "local": LIBRARY_ROOT / "skills-local",
}
PLAYBOOK_DIR = LIBRARY_ROOT / "playbooks"


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


def discover_skills(include_local: bool = False) -> list[Skill]:
    """Discover skills.

    Canonical only by default — the set the server's `instructions` text and
    prompt registration use. Pass `include_local=True` to add the local
    profile too (used by `list_skills` and skill lookup by name).

    Re-scans the directories on every call: a server process can run for a
    long session (README's `claude mcp add` registers it once per client),
    and this repo actively edits skills, so a cache would serve a stale
    catalog until restart. The scan is a handful of small markdown files —
    not worth trading correctness for.
    """
    profiles = PROFILES if include_local else {"canonical": PROFILES["canonical"]}
    skills: list[Skill] = []
    for profile, root in profiles.items():
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


def find_skill(name: str, profile: str) -> Skill | None:
    matches = [s for s in discover_skills(include_local=True) if s.name == name]
    if not matches:
        return None
    for s in matches:
        if s.profile == profile:
            return s
    return matches[0]


def list_skills_text() -> str:
    lines = []
    for s in discover_skills(include_local=True):
        desc = s.description.split(". ")[0].rstrip(".")
        lines.append(f"- {s.name} [{s.profile}] — {desc}")
    if not lines:
        return f"No skills found under {LIBRARY_ROOT} — check WAYS_OF_WORKING_LIBRARY."
    return "\n".join(lines)


def get_skill_text(name: str, profile: str = "canonical") -> str:
    skill = find_skill(name, profile)
    if skill is None:
        available = ", ".join(sorted({s.name for s in discover_skills(include_local=True)}))
        return f"Unknown skill '{name}'. Available: {available}"
    return skill.body()


def read_playbook(name: str) -> str:
    if not PLAYBOOK_DIR.is_dir():
        return f"No playbooks directory at {PLAYBOOK_DIR}."
    books = {p.stem.lower(): p for p in sorted(PLAYBOOK_DIR.glob("*.md"))}
    if not name:
        return "\n".join(f"- {stem}" for stem in books)
    book = books.get(name.lower())
    if book is None:
        return f"Unknown playbook '{name}'. Available: {', '.join(books)}"
    return book.read_text(encoding="utf-8")


def build_instructions() -> str:
    """Generate the server's `instructions` text from the discovered skill set.

    No hardcoded skill count or name list — it stays correct as skills are
    added or removed.
    """
    names = sorted({s.name for s in discover_skills()})
    catalog = ", ".join(names)
    return (
        "Quality-process library: judgment-dense skills covering software "
        "engineering, ops/incidents, codebase navigation, and non-engineering work.\n"
        f"Skills: {catalog}.\n"
        "Call list_skills to see the full catalog with descriptions; "
        "get_skill/get_playbook to load one; route for model-selection guidance. "
        "Prompts named after skills inject the skill text plus your task."
    )


# Deterministic first-pass hints; the real judgment lives in ROUTING.md, which
# route() returns for the caller to apply. Honest heuristic, not fake intelligence.
#
# Each entry is (patterns, hint): the hint fires if ANY pattern in the tuple
# matches. Splitting stem-friendly tokens (which may carry a trailing `\w*`)
# from short, code-like tokens (`PR`, `CI`, `down`, `ui`, `ux`, `css` — bounded
# with `\b...\b` and no `\w*`) keeps the short tokens from swallowing unrelated
# words: `\bdown\w*\b` used to match "download"; `\bPR\w*\b` (case-insensitive)
# used to match "prove"; `\bCI\w*\b` (case-insensitive) used to match "cite".
_ROUTE_HINTS: list[tuple[tuple[str, ...], str]] = [
    (
        (r"(?i)\b(architect|design|schema|data model|api design|migration plan)\b",),
        "signals architecture/one-way-door work → highest available tier",
    ),
    (
        (
            r"(?i)\b(frontend|layout|responsive|component|styling|stylesheet|design.?system|theme|accessib)\w*\b",
            r"(?i)\b(ui|ux|css)\b",
        ),
        "signals UI/visual design work → frontend-design skill, commit to tokens before components",
    ),
    (
        (r"(?i)\b((working|operating) (process|model)|how (I|we) like to work|session start|project kickoff|new project setup)\b",),
        "signals session/project setup → apply-working-process skill, adopt the standard process before task work",
    ),
    (
        (r"(?i)\b(race|deadlock|heisenbug|flaky|intermittent|concurren)\w*\b",),
        "signals gnarly debugging → high tier",
    ),
    (
        (
            # "auth" variants deliberately exclude author/authoring
            r"(?i)\b(security|payment|billing|secret)\w*\b",
            r"(?i)\bauth(n|z|entication|orization|enticate|orize[sd]?)?\b",
        ),
        "signals high-stakes review → high tier with fresh context (skill: sec-audit)",
    ),
    (
        (
            r"(?i)\b(incident|outage|degraded|pager|on.?call|alert)\w*\b",
            r"(?i)\bdown\b",
        ),
        "signals production incident → use incident skill, mitigate before diagnosing",
    ),
    (
        (r"(?i)\b(postmortem|retrospective|blameless|root.?cause)\w*\b",),
        "signals incident retrospective → postmortem skill",
    ),
    (
        (r"(?i)\b(deploy|release|rollout|canary|feature.?flag|publish)\w*\b",),
        "signals release work → release skill, verify + stage + watch",
    ),
    (
        (r"(?i)\b(onboard|unfamiliar|new.?repo|picking.?up|orient)\w*\b",),
        "signals codebase orientation → onboard skill",
    ),
    (
        (r"(?i)\b(estimat|how.?long|how.?big|scope|effort|deadline)\w*\b",),
        "signals estimation → estimate skill, deliver a range not a number",
    ),
    (
        (
            r"(?i)\b(pull.?request|branch|commit|code.?review.?workflow)\w*\b",
            r"\bPRs?\b",  # case-sensitive: lowercase "pr" is too often unrelated (e.g. public relations)
        ),
        "signals PR prep/review work → pr-workflow skill",
    ),
    (
        (r"(?i)\b(optim|slow|latency|throughput|memory.?leak|profile|bottleneck)\w*\b",),
        "signals performance work → perf skill, profile before touching code",
    ),
    (
        (
            r"(?i)\b(pipeline|build.?red|build.?fail|flak)\w*\b",
            r"(?i)\bCI\b",
        ),
        "signals broken build → ci-triage skill",
    ),
    (
        (r"(?i)\b(upgrad|migrat|deprecat|breaking.?change|data.?migration|schema.?change)\w*\b",),
        "signals migration/upgrade work → migrate skill",
    ),
    (
        (r"(?i)\b(simplif|clean.?up|declutter|dead.?code|unused|remove.?boilerplate)\w*\b",),
        "signals cleanup pass → declutter skill (behavior-preserving only)",
    ),
    (
        (r"(?i)\b(dataset|metric|dashboard|experiment|A/B|analyze.?data|SQL.?query)\w*\b",),
        "signals data analysis work → data-analysis skill",
    ),
    (
        (r"(?i)\b(brainstorm|ideation|options|alternative|stuck|generate.?ideas?)\w*\b",),
        "signals ideation → brainstorm skill, generate wide before judging",
    ),
    (
        (r"(?i)\b(prompt.?engineer|system.?prompt|LLM.?feature|eval.?set)\w*\b",),
        "signals prompt engineering → prompt-eng skill",
    ),
    (
        (r"(?i)\b(how.?does.+work|where.+live|research.+codebase|document.+behavior)\w*\b",),
        "signals codebase research → research-codebase skill, documentarian stance",
    ),
    (
        (r"(?i)\b(rename|boilerplate|scaffold|convert|reformat|bulk|batch)\w*\b",),
        "signals mechanical work → Haiku/local tier",
    ),
    (
        (r"(?i)\b(summar|commit message|changelog|docstring)\w*\b",),
        "signals light text work → Haiku tier",
    ),
]


def route(task_description: str) -> str:
    """Recommend which model tier should handle a task. Returns keyword-based
    first-pass hints plus the full ROUTING playbook; apply the playbook's
    principles — the hints are only a starting point."""
    hints = [
        hint
        for patterns, hint in _ROUTE_HINTS
        if any(re.search(pattern, task_description) for pattern in patterns)
    ]
    hint_text = (
        "Keyword hints for this task:\n" + "\n".join(f"- {h}" for h in hints)
        if hints
        else "No keyword hints matched — apply the playbook's principles directly."
    )
    playbook = read_playbook("routing")
    return (
        f"{hint_text}\n\n"
        "Apply the routing playbook below (principles beat keywords; "
        "route by cost-of-being-wrong, not difficulty):\n\n"
        f"{playbook}"
    )
