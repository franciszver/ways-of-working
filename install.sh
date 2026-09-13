#!/usr/bin/env bash
# install.sh — deploy ways-of-working into your environments.
#
# Smoke-tested 2026-07-06 (all targets, idempotent reruns, error cases,
# against a scratch HOME). --dry-run previews any run.
#
# The Claude Code plugin (see .claude-plugin/) is the headline path for
# Claude Code now — `claude plugin marketplace add` + `claude plugin
# install`. This script still covers every other target and the
# link/check/profile workflows below.
#
# Usage:
#   ./install.sh --claude-user [--profile frontier|local] [--link] [--force]
#   ./install.sh --claude-project DIR [--profile frontier|local] [--link] [--force]
#   ./install.sh --hooks DIR
#   ./install.sh --antigravity DIR
#   ./install.sh --agents-md DIR
#   ./install.sh --cursor DIR
#   ./install.sh --gemini [DIR|global]
#   ./install.sh --mcp
#   ./install.sh --check
#   Options: --dry-run  --force  --link  --profile frontier|local  -h/--help
#
# Profiles: 'frontier' installs skills/ + agents/ + global-frontier CLAUDE.md rules
# (paid models — lean discipline). 'local' installs skills-local/ + global-local
# rules (free local models — thoroughness discipline). One profile per setup;
# the packs share skill names by design.
#
# A marker file ($HOME/.claude/skills/.ways-of-working-profile) records
# which profile --claude-user last installed. Requesting the other profile
# without --force is refused; with --force, skills that belong only to the
# previous profile's pack are removed before the new pack is installed.
#
# --link installs each skill/agent as a symlink into this library instead
# of a copy — for personal installs, so edits to the library apply without
# reinstalling. --check compares the installed copies under
# $HOME/.claude/skills and $HOME/.claude/agents against the library and
# lists any file that differs (symlinked installs never drift); it exits 1
# if drift is found.

set -euo pipefail

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=0
FORCE=0
LINK=0
PROFILE="frontier"
ACTIONS=()
ARG_CLAUDE_PROJECT=""
ARG_HOOKS=""
ARG_ANTIGRAVITY=""
ARG_AGENTS_MD=""
ARG_CURSOR=""
ARG_GEMINI=""

usage() { # $1 = exit code (default 1)
  sed -n '2,39p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit "${1:-1}"
}

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
    --check)          ACTIONS+=(check) ;;
    --profile)        PROFILE="${2:?--profile needs frontier|local}"; shift ;;
    --link)           LINK=1 ;;
    --dry-run)        DRY_RUN=1 ;;
    --force)          FORCE=1 ;;
    -h|--help)        usage 0 ;;
    *) echo "Unknown option: $1"; usage 1 ;;
  esac
  shift
done

[ ${#ACTIONS[@]} -gt 0 ] || usage 1
case "$PROFILE" in frontier|local) ;; *) echo "Invalid --profile: $PROFILE"; exit 1 ;; esac

for_each_skill_dir() { # $1 = source root (skills|skills-local), $2 = callback fn, $3.. = extra args passed after (dir, name)
  local src="$1" cb="$2" dir name
  shift 2
  for dir in "$LIB/$src"/*/; do
    [ -f "${dir}SKILL.md" ] || continue
    name="$(basename "$dir")"
    "$cb" "$dir" "$name" "$@"
  done
}

profile_layout() { # $1 = profile name (frontier|local); echoes "SKILLS_SUBDIR AGENTS_FLAG"
  # AGENTS_FLAG is the literal word "agents" when the profile installs
  # agents/, or "-" when it does not. Single source of truth for which
  # content each profile carries — keep in sync with the profile
  # descriptions in the usage banner above.
  case "$1" in
    frontier) echo "skills agents" ;;
    local)    echo "skills-local -" ;;
    *) echo "Unknown profile: $1" >&2; return 1 ;;
  esac
}

_copy_skill_dir_cb() { # $1 = source dir, $2 = name, $3 = dest skills dir
  # Safe-by-default like every other target: existing skill dirs are skipped
  # (users tune installed skills), --force refreshes them from the library.
  # --link installs a symlink to the library dir instead of a copy.
  local dir="$1" name="$2" dest="$3"
  if [ -e "$dest/$name" ] && [ "$FORCE" -eq 0 ]; then
    note "skill exists, skipping (use --force to refresh): $dest/$name"
    return 0
  fi
  run rm -rf "${dest:?}/$name"
  if [ "$LINK" -eq 1 ]; then
    note "skill (link): $name -> $dest/$name"
    run ln -s "${dir%/}" "$dest/$name"
  else
    note "skill: $name -> $dest/$name"
    run cp -R "$dir" "$dest/$name"
  fi
}

copy_skill_dirs() { # $1 = source root (skills|skills-local), $2 = dest skills dir
  local src="$1" dest="$2"
  run mkdir -p "$dest"
  for_each_skill_dir "$src" _copy_skill_dir_cb "$dest"
}

append_guarded() { # $1 = snippet file, $2 = target file, $3 = marker
  local snippet="$1" target="$2" marker="$3"
  if [ -f "$target" ] && grep -qF "$marker" "$target"; then
    note "already present (marker found), skipping append: $target"
    return 0
  fi
  if [ -f "$target" ]; then
    local suffix="${marker#*:}"
    suffix="${suffix% -->}"
    if grep -qE "<!-- [a-z0-9-]+:${suffix} -->" "$target"; then
      note "migrated guard marker in $target"
      if [ "$DRY_RUN" -eq 0 ]; then
        sed -i -E "s|<!-- [a-z0-9-]+:${suffix} -->|${marker}|" "$target"
      else
        echo "[dry-run] migrate guard marker in $target"
      fi
      return 0
    fi
  fi
  note "appending $(basename "$snippet") -> $target"
  if [ "$DRY_RUN" -eq 0 ]; then
    mkdir -p "$(dirname "$target")"
    { echo ""; echo "$marker"; cat "$snippet"; } >> "$target"
  else
    echo "[dry-run] append $snippet >> $target"
  fi
}

copy_file_safe() { # $1 = src, $2 = dest, $3 = 1 to honor --link (default: 0)
  local allow_link="${3:-0}"
  if [ -e "$2" ] && [ "$FORCE" -eq 0 ]; then
    note "exists, skipping (use --force to overwrite): $2"
    return 0
  fi
  run mkdir -p "$(dirname "$2")"
  if [ "$allow_link" -eq 1 ] && [ "$LINK" -eq 1 ]; then
    note "file (link): $1 -> $2"
    run rm -f "$2"
    run ln -s "$1" "$2"
  else
    note "file: $1 -> $2"
    run cp "$1" "$2"
  fi
}

profile_marker_path() { echo "$1/skills/.ways-of-working-profile"; } # $1 = base (e.g. $HOME/.claude)

check_profile_marker() { # $1 = base; refuses a profile switch without --force
  local base="$1" marker installed
  marker="$(profile_marker_path "$base")"
  [ -f "$marker" ] || return 0
  installed="$(cat "$marker")"
  [ "$installed" = "$PROFILE" ] && return 0
  if [ "$FORCE" -ne 1 ]; then
    echo "Installed profile is '$installed', requested '$PROFILE'." >&2
    echo "Re-run with --force to switch (this removes skills that belong only to the '$installed' pack)." >&2
    exit 1
  fi
  remove_other_profile_skills "$base" "$installed"
}

_remove_other_profile_skill_cb() { # $1 = dir, $2 = name, $3 = base, $4 = new_src, $5 = other profile name
  local dir="$1" name="$2" base="$3" new_src="$4" other="$5"
  [ -d "$LIB/$new_src/$name" ] && return 0 # shared name, the new pack keeps it
  if [ -e "$base/skills/$name" ]; then
    note "removing skill from previous profile ($other), absent from $PROFILE pack: $name"
    run rm -rf "${base:?}/skills/${name:?}"
  fi
}

remove_other_profile_skills() { # $1 = base, $2 = previous profile name
  local base="$1" other="$2" other_src other_agents new_src new_agents
  read -r other_src other_agents <<< "$(profile_layout "$other")"
  read -r new_src new_agents <<< "$(profile_layout "$PROFILE")"
  for_each_skill_dir "$other_src" _remove_other_profile_skill_cb "$base" "$new_src" "$other"
  # An agents flag present on the old profile but not the new one means
  # leaving that profile removes its agents too.
  if [ "$other_agents" = "agents" ] && [ "$new_agents" != "agents" ]; then
    local f name
    for f in "$LIB"/agents/*.md; do
      name="$(basename "$f")"
      if [ -e "$base/agents/$name" ]; then
        note "removing agent from previous profile ($other): $name"
        run rm -f "${base:?}/agents/${name:?}"
      fi
    done
  fi
}

write_profile_marker() { # $1 = base
  local base="$1" marker
  marker="$(profile_marker_path "$base")"
  run mkdir -p "$base/skills"
  if [ "$DRY_RUN" -eq 0 ]; then
    echo "$PROFILE" > "$marker"
  else
    echo "[dry-run] write '$PROFILE' > $marker"
  fi
}

do_claude_user() {
  local base="$HOME/.claude" src_subdir agents_flag
  check_profile_marker "$base"
  read -r src_subdir agents_flag <<< "$(profile_layout "$PROFILE")"
  copy_skill_dirs "$src_subdir" "$base/skills"
  if [ "$agents_flag" = "agents" ]; then
    run mkdir -p "$base/agents"
    local f
    for f in "$LIB"/agents/*.md; do copy_file_safe "$f" "$base/agents/$(basename "$f")" 1; done
  fi
  if [ "$PROFILE" = "frontier" ]; then
    append_guarded "$LIB/claude-md/global-frontier.md" "$base/CLAUDE.md" "<!-- ways-of-working:frontier -->"
  else
    append_guarded "$LIB/claude-md/global-local.md" "$base/CLAUDE.md" "<!-- ways-of-working:local -->"
  fi
  write_profile_marker "$base"
  note "done. If ~/.claude/skills was created just now, restart Claude Code once."
}

do_claude_project() {
  local proj="$ARG_CLAUDE_PROJECT" base="$ARG_CLAUDE_PROJECT/.claude"
  [ -d "$proj" ] || { echo "No such directory: $proj"; exit 1; }
  if [ "$PROFILE" = "frontier" ]; then
    copy_skill_dirs "skills" "$base/skills"
    run mkdir -p "$base/agents"
    local f
    for f in "$LIB"/agents/*.md; do copy_file_safe "$f" "$base/agents/$(basename "$f")" 1; done
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
    note "settings.json exists — merging hooks/settings-snippet.json into it."
    if [ "$DRY_RUN" -eq 0 ]; then
      python3 "$LIB/scripts/merge-hooks.py" "$base/settings.json" "$LIB/hooks/settings-snippet.json"
    else
      echo "[dry-run] merge hooks/settings-snippet.json into $base/settings.json"
    fi
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

  claude mcp add ways-of-working -- uv run --directory "$LIB/mcp-server" server.py

Generic mcpServers JSON:
  {"mcpServers": {"ways-of-working": {"command": "uv",
    "args": ["run", "--directory", "$LIB/mcp-server", "server.py"]}}}

If this server was registered under its previous name, remove that registration
first (claude mcp list shows it), and re-export the library-root env var under
its new name WAYS_OF_WORKING_LIBRARY.
EOF
}

_report_dir_diff() { # $1 = library dir, $2 = installed dir; sets DRIFT=1 and prints DRIFT lines on any difference
  local lib_dir="${1%/}" installed_dir="$2" out line
  out="$(diff -rq "$lib_dir" "$installed_dir" 2>&1)" || true
  if [ -n "$out" ]; then
    while IFS= read -r line; do
      echo "DRIFT: $line"
    done <<< "$out"
    DRIFT=1
  fi
}

_check_skill_dir_cb() { # $1 = dir, $2 = name, $3 = base
  local dir="$1" name="$2" base="$3"
  if [ ! -e "$base/skills/$name" ]; then
    echo "DRIFT: skill not installed: $name"
    DRIFT=1
    return 0
  fi
  if [ -L "$base/skills/$name" ]; then
    return 0 # symlinked install, never drifts
  fi
  _report_dir_diff "$dir" "$base/skills/$name"
}

do_check() {
  local base="$HOME/.claude" marker="" profile="frontier" src_skills agents_flag
  marker="$(profile_marker_path "$base")"
  [ -f "$marker" ] && profile="$(cat "$marker")"
  read -r src_skills agents_flag <<< "$(profile_layout "$profile")"
  note "checking installed skills ($profile profile) against $src_skills/ ..."

  DRIFT=0
  for_each_skill_dir "$src_skills" _check_skill_dir_cb "$base"

  if [ "$agents_flag" = "agents" ]; then
    if [ ! -d "$base/agents" ]; then
      echo "DRIFT: agents not installed"
      DRIFT=1
    else
      _report_dir_diff "$LIB/agents" "$base/agents"
    fi
  fi

  if [ "$DRIFT" -eq 1 ]; then
    echo "Drift found — see DRIFT lines above."
    exit 1
  fi
  note "no drift: installed copies match the library."
}

for action in "${ACTIONS[@]}"; do "do_$action"; done
note "all requested installs processed."
