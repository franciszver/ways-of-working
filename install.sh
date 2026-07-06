#!/usr/bin/env bash
# install.sh — deploy the fable-quality-library into your environments.
#
# Smoke-tested 2026-07-06 (all targets, idempotent reruns, error cases,
# against a scratch HOME). --dry-run previews any run.
#
# Usage:
#   ./install.sh --claude-user [--profile frontier|local]
#   ./install.sh --claude-project DIR [--profile frontier|local]
#   ./install.sh --hooks DIR
#   ./install.sh --antigravity DIR
#   ./install.sh --agents-md DIR
#   ./install.sh --cursor DIR
#   ./install.sh --gemini [DIR|global]
#   ./install.sh --mcp
#   Options: --dry-run  --force
#
# Profiles: 'frontier' installs skills/ + agents/ + global-frontier CLAUDE.md rules
# (paid models — lean discipline). 'local' installs skills-local/ + global-local
# rules (free local models — thoroughness discipline). One profile per setup;
# the packs share skill names by design.

set -euo pipefail

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=0
FORCE=0
PROFILE="frontier"
ACTIONS=()
ARG_CLAUDE_PROJECT=""
ARG_HOOKS=""
ARG_ANTIGRAVITY=""
ARG_AGENTS_MD=""
ARG_CURSOR=""
ARG_GEMINI=""

usage() { sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 1; }

run() {
  if [ "$DRY_RUN" -eq 1 ]; then echo "[dry-run] $*"; else "$@"; fi
}

note() { echo "==> $*"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --claude-user)    ACTIONS+=(claude_user) ;;
    --claude-project) ACTIONS+=(claude_project); ARG_CLAUDE_PROJECT="${2:?--claude-project needs DIR}"; shift ;;
    --hooks)          ACTIONS+=(hooks);          ARG_HOOKS="${2:?--hooks needs DIR}"; shift ;;
    --antigravity)    ACTIONS+=(antigravity);    ARG_ANTIGRAVITY="${2:?--antigravity needs DIR}"; shift ;;
    --agents-md)      ACTIONS+=(agents_md);      ARG_AGENTS_MD="${2:?--agents-md needs DIR}"; shift ;;
    --cursor)         ACTIONS+=(cursor);         ARG_CURSOR="${2:?--cursor needs DIR}"; shift ;;
    --gemini)         ACTIONS+=(gemini);         ARG_GEMINI="${2:?--gemini needs DIR or 'global'}"; shift ;;
    --mcp)            ACTIONS+=(mcp) ;;
    --profile)        PROFILE="${2:?--profile needs frontier|local}"; shift ;;
    --dry-run)        DRY_RUN=1 ;;
    --force)          FORCE=1 ;;
    -h|--help)        usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
  shift
done

[ ${#ACTIONS[@]} -gt 0 ] || usage
case "$PROFILE" in frontier|local) ;; *) echo "Invalid --profile: $PROFILE"; exit 1 ;; esac

copy_skill_dirs() { # $1 = source root (skills|skills-local), $2 = dest skills dir
  # Safe-by-default like every other target: existing skill dirs are skipped
  # (users tune installed skills), --force refreshes them from the library.
  local src="$1" dest="$2" dir name
  run mkdir -p "$dest"
  for dir in "$LIB/$src"/*/; do
    [ -f "${dir}SKILL.md" ] || continue
    name="$(basename "$dir")"
    if [ -d "$dest/$name" ] && [ "$FORCE" -eq 0 ]; then
      note "skill exists, skipping (use --force to refresh): $dest/$name"
      continue
    fi
    note "skill: $name -> $dest/$name"
    run rm -rf "${dest:?}/$name"
    run cp -R "$dir" "$dest/$name"
  done
}

append_guarded() { # $1 = snippet file, $2 = target file, $3 = marker
  local snippet="$1" target="$2" marker="$3"
  if [ -f "$target" ] && grep -qF "$marker" "$target"; then
    note "already present (marker found), skipping append: $target"
    return 0
  fi
  note "appending $(basename "$snippet") -> $target"
  if [ "$DRY_RUN" -eq 0 ]; then
    mkdir -p "$(dirname "$target")"
    { echo ""; echo "$marker"; cat "$snippet"; } >> "$target"
  else
    echo "[dry-run] append $snippet >> $target"
  fi
}

copy_file_safe() { # $1 = src, $2 = dest
  if [ -e "$2" ] && [ "$FORCE" -eq 0 ]; then
    note "exists, skipping (use --force to overwrite): $2"
    return 0
  fi
  note "file: $1 -> $2"
  run mkdir -p "$(dirname "$2")"
  run cp "$1" "$2"
}

do_claude_user() {
  local base="$HOME/.claude"
  if [ "$PROFILE" = "frontier" ]; then
    copy_skill_dirs "skills" "$base/skills"
    run mkdir -p "$base/agents"
    local f
    for f in "$LIB"/agents/*.md; do copy_file_safe "$f" "$base/agents/$(basename "$f")"; done
    append_guarded "$LIB/claude-md/global-frontier.md" "$base/CLAUDE.md" "<!-- fable-quality-library:frontier -->"
  else
    copy_skill_dirs "skills-local" "$base/skills"
    append_guarded "$LIB/claude-md/global-local.md" "$base/CLAUDE.md" "<!-- fable-quality-library:local -->"
  fi
  note "done. If ~/.claude/skills was created just now, restart Claude Code once."
}

do_claude_project() {
  local proj="$ARG_CLAUDE_PROJECT" base="$ARG_CLAUDE_PROJECT/.claude"
  [ -d "$proj" ] || { echo "No such directory: $proj"; exit 1; }
  if [ "$PROFILE" = "frontier" ]; then
    copy_skill_dirs "skills" "$base/skills"
    run mkdir -p "$base/agents"
    local f
    for f in "$LIB"/agents/*.md; do copy_file_safe "$f" "$base/agents/$(basename "$f")"; done
  else
    copy_skill_dirs "skills-local" "$base/skills"
  fi
  if [ ! -f "$proj/CLAUDE.md" ]; then
    copy_file_safe "$LIB/claude-md/project-template.md" "$proj/CLAUDE.md"
    note "created CLAUDE.md from template — fill in the marked sections."
  else
    note "CLAUDE.md exists, untouched. Template for reference: claude-md/project-template.md"
  fi
}

do_hooks() {
  local proj="$ARG_HOOKS" base="$ARG_HOOKS/.claude"
  [ -d "$proj" ] || { echo "No such directory: $proj"; exit 1; }
  run mkdir -p "$base/hooks"
  local f
  for f in "$LIB"/hooks/scripts/*.sh; do
    copy_file_safe "$f" "$base/hooks/$(basename "$f")"
    run chmod +x "$base/hooks/$(basename "$f")"
  done
  if [ ! -f "$base/settings.json" ]; then
    copy_file_safe "$LIB/hooks/settings-snippet.json" "$base/settings.json"
  else
    note "settings.json exists — merge hooks/settings-snippet.json into it manually."
  fi
  note "restart the Claude Code session, then run /hooks to confirm registration."
  note "optional test gate: echo 'npm test' > $proj/.claude/test-command"
}

do_antigravity() {
  local proj="$ARG_ANTIGRAVITY"
  [ -d "$proj" ] || { echo "No such directory: $proj"; exit 1; }
  run mkdir -p "$proj/.agent/rules" "$proj/.agent/workflows"
  local f
  for f in "$LIB"/antigravity/rules/*.md;     do copy_file_safe "$f" "$proj/.agent/rules/$(basename "$f")"; done
  for f in "$LIB"/antigravity/workflows/*.md; do copy_file_safe "$f" "$proj/.agent/workflows/$(basename "$f")"; done
  note "global baseline: paste antigravity/rules/baseline.md into Antigravity's Manage Rules UI."
}

do_agents_md() {
  local proj="$ARG_AGENTS_MD"
  [ -d "$proj" ] || { echo "No such directory: $proj"; exit 1; }
  copy_file_safe "$LIB/ports/agents-md/AGENTS.md" "$proj/AGENTS.md"
  note "fill in the 'Project commands' section of AGENTS.md."
}

do_cursor() {
  local proj="$ARG_CURSOR"
  [ -d "$proj" ] || { echo "No such directory: $proj"; exit 1; }
  run mkdir -p "$proj/.cursor/rules"
  local f
  for f in "$LIB"/ports/cursor/*.mdc; do copy_file_safe "$f" "$proj/.cursor/rules/$(basename "$f")"; done
}

do_gemini() {
  local dest
  if [ "$ARG_GEMINI" = "global" ]; then dest="$HOME/.gemini/commands"; else
    [ -d "$ARG_GEMINI" ] || { echo "No such directory: $ARG_GEMINI"; exit 1; }
    dest="$ARG_GEMINI/.gemini/commands"
  fi
  run mkdir -p "$dest"
  local f
  for f in "$LIB"/ports/gemini/commands/*.toml; do copy_file_safe "$f" "$dest/$(basename "$f")"; done
  note "context file: see ports/gemini/README.md (copy AGENTS.md as GEMINI.md, or set context.fileName)."
}

do_mcp() {
  cat <<EOF
Register the MCP server (see mcp-server/README.md for the smoke test first):

  claude mcp add fable-quality -- uv run --directory "$LIB/mcp-server" server.py

Generic mcpServers JSON:
  {"mcpServers": {"fable-quality": {"command": "uv",
    "args": ["run", "--directory", "$LIB/mcp-server", "server.py"]}}}
EOF
}

for action in "${ACTIONS[@]}"; do "do_$action"; done
note "all requested installs processed."
