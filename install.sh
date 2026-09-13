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
#   ./install.sh --skills DIR
#   ./install.sh --mcp
#   ./install.sh --check
#   Options: --dry-run  --force  --link  --profile frontier|local  -h/--help
#
# Profiles: 'frontier' installs the committed Claude Code profile
# (build/claude-code/skills — canonical skills/ plus Claude-Code-only
# frontmatter from scripts/profile-claude-code.yaml, generated and
# committed like the antigravity stubs) + agents/ + playbooks/ (also
# committed; playbooks/ROUTING.md is referenced by name from installed
# skills, so it travels with them) + global-frontier CLAUDE.md rules
# (paid models — lean discipline). 'local' installs skills-local/ +
# global-local rules (free local models — thoroughness discipline). One
# profile per setup; the packs share skill names by design. No
# python3/PyYAML needed to install either profile — a change to a
# canonical skill or to scripts/profile-claude-code.yaml needs
# `python3 scripts/build-profile.py` run once (a dev step, enforced in CI
# by `python3 scripts/build-profile.py --check`) before a frontier
# install picks it up.
#
# A marker file ($HOME/.claude/skills/.ways-of-working-profile) records
# which profile --claude-user last installed. Requesting the other profile
# without --force is refused; with --force, skills that belong only to the
# previous profile's pack are removed before the new pack is installed.
#
# --link installs each skill/agent as a symlink into this library instead
# of a copy — for personal installs, so edits to the library apply without
# reinstalling. --check compares the installed copies under
# $HOME/.claude/skills, $HOME/.claude/agents, and $HOME/.claude/playbooks
# (frontier only — flagged as drift if present under the local profile)
# against the library and lists any file that differs (symlinked installs
# never drift); it exits 1 if drift is found.
#
# The CLAUDE.md rules block --claude-user appends is guarded by begin/end
# markers. --force refreshes it in place between those markers; a block
# with no end marker (installed before this refresh support existed) is
# backed up to CLAUDE.md.bak first, since the boundary is then only the
# next marker or EOF and may include text you added by hand. --check
# reports drift in the block (or LEGACY if it has no end marker yet).
#
# --skills DIR copies (or, with --link, symlinks) every skills/*/ directory
# into DIR, for tools that read Agent Skills natively: Cursor
# (`.cursor/skills`), the paid-tier Gemini CLI (`~/.gemini/skills`),
# Antigravity (`.agents/skills`).

set -euo pipefail

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=0
FORCE=0
LINK=0
PROFILE="frontier"
PROFILE_EXPLICIT=0
ACTIONS=()
ARG_CLAUDE_PROJECT=""
ARG_HOOKS=""
ARG_ANTIGRAVITY=""
ARG_AGENTS_MD=""
ARG_CURSOR=""
ARG_SKILLS=""

usage() { # $1 = exit code (default 1); prints the header comment block (line 2 to the first blank line after it)
  awk 'NR==1 { next } /^$/ { exit } { sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}"
  exit "${1:-1}"
}

run() {
  if [ "$DRY_RUN" -eq 1 ]; then echo "[dry-run] $*"; else "$@"; fi
}

note() { echo "==> $*"; }

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --claude-user)    ACTIONS+=(claude_user) ;;
      --claude-project) ACTIONS+=(claude_project); ARG_CLAUDE_PROJECT="${2:?--claude-project needs DIR}"; shift ;;
      --hooks)          ACTIONS+=(hooks);          ARG_HOOKS="${2:?--hooks needs DIR}"; shift ;;
      --antigravity)    ACTIONS+=(antigravity);    ARG_ANTIGRAVITY="${2:?--antigravity needs DIR}"; shift ;;
      --agents-md)      ACTIONS+=(agents_md);      ARG_AGENTS_MD="${2:?--agents-md needs DIR}"; shift ;;
      --cursor)         ACTIONS+=(cursor);         ARG_CURSOR="${2:?--cursor needs DIR}"; shift ;;
      --skills)         ACTIONS+=(skills);         ARG_SKILLS="${2:?--skills needs DIR}"; shift ;;
      --mcp)            ACTIONS+=(mcp) ;;
      --check)          ACTIONS+=(check) ;;
      --profile)        PROFILE="${2:?--profile needs frontier|local}"; PROFILE_EXPLICIT=1; shift ;;
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
}

for_each_skill_dir() { # $1 = source root (skills|skills-local), $2 = callback fn, $3.. = extra args passed after (dir, name)
  local src="$1" cb="$2" dir name
  shift 2
  for dir in "$LIB/$src"/*/; do
    [ -f "${dir}SKILL.md" ] || continue
    name="$(basename "$dir")"
    "$cb" "$dir" "$name" "$@"
  done
}

profile_layout() { # $1 = profile name (frontier|local); echoes "SKILLS_SUBDIR AGENTS_FLAG MARKER_SUFFIX SNIPPET_BASENAME"
  # AGENTS_FLAG is the literal word "agents" when the profile installs
  # agents/, or "-" when it does not. MARKER_SUFFIX is the profile suffix
  # used in the CLAUDE.md guard marker (<!-- ways-of-working:SUFFIX -->);
  # SNIPPET_BASENAME is the claude-md/ file appended for that marker.
  # Single source of truth for which content each profile carries — keep
  # in sync with the profile descriptions in the usage banner above.
  case "$1" in
    frontier) echo "build/claude-code/skills agents frontier global-frontier.md" ;;
    local)    echo "skills-local - local global-local.md" ;;
    *) echo "Unknown profile: $1" >&2; return 1 ;;
  esac
}

require_layout() { # $1 = profile name, $2 = context for the error message; echoes profile_layout's output or exits 1
  local p="$1" ctx="$2" layout
  if ! layout="$(profile_layout "$p")"; then
    echo "Unknown profile '$p' ($ctx)." >&2
    exit 1
  fi
  echo "$layout"
}

infer_installed_profile() { # $1 = base; echoes frontier|local, or nothing if no install is detected
  local base="$1" dir name
  if [ -d "$base/agents" ] && [ -n "$(find "$base/agents" -mindepth 1 -print -quit 2>/dev/null)" ]; then
    echo "frontier"
    return 0
  fi
  if [ -d "$base/skills" ]; then
    for dir in "$LIB/skills"/*/; do
      [ -f "${dir}SKILL.md" ] || continue
      name="$(basename "$dir")"
      if [ -e "$base/skills/$name" ] && [ ! -d "$LIB/skills-local/$name" ]; then
        echo "frontier" # a frontier-only skill name is installed
        return 0
      fi
    done
    if [ -n "$(find "$base/skills" -mindepth 1 -print -quit 2>/dev/null)" ]; then
      echo "local"
      return 0
    fi
  fi
  echo ""
}

resolve_target() { # $1 = path; echoes the resolved real path (dereferences a symlink), even if it doesn't exist yet
  local path="$1"
  if [ -e "$path" ]; then
    readlink -f "$path"
  else
    echo "$path"
  fi
}

count_marker_lines() { # $1 = target file, $2 = marker line; counts exact-line matches, tolerating a trailing CR (CRLF files)
  local target="$1" marker="$2"
  [ -f "$target" ] || { echo 0; return 0; }
  awk -v marker="$marker" '{ line = $0; sub(/\r$/, "", line); if (line == marker) c++ } END { print c + 0 }' "$target"
}

guarded_block_range() { # $1 = target file, $2 = begin marker line; echoes "START END LEGACY" or nothing if the marker is absent
  # END is the line of the matching end marker (LEGACY=0), or the line
  # before the next "<!-- ways-of-working:" marker / EOF when no end
  # marker closes the block (LEGACY=1) — this also covers a duplicate of
  # the same begin marker, which counts as "the next marker". Comparisons
  # strip a trailing \r so CRLF files still match exactly.
  local target="$1" marker="$2" end_marker
  end_marker="${marker/ways-of-working:/\/ways-of-working:}"
  awk -v marker="$marker" -v end_marker="$end_marker" '
    {
      line = $0
      sub(/\r$/, "", line)
    }
    start == 0 && line == marker { start = NR; next }
    start != 0 && end == 0 {
      if (line == end_marker) { end = NR; legacy = 0; exit }
      if (index(line, "<!-- ways-of-working:") == 1) { end = NR - 1; legacy = 1; exit }
    }
    END {
      if (start != 0 && end == 0) { end = NR; legacy = 1 }
      if (start != 0) print start, end, legacy
    }
  ' "$target"
}

_maybe_backup_legacy() { # $1 = target, $2 = legacy flag (0/1); backs up and warns before a write touches a legacy block
  local target="$1" legacy="$2"
  if [ "$legacy" -eq 1 ]; then
    cp "$target" "${target}.bak"
    echo "WARNING: legacy guarded block (no end marker) in $target — backed up to ${target}.bak." >&2
    echo "         Any personal text after the old block was moved there; re-add it below the new end marker." >&2
  fi
}

_finish_write() { # $1 = tmp file with new content, $2 = resolved real path to write to; preserves the target's mode
  local tmp="$1" resolved="$2" perm
  if [ -e "$resolved" ]; then
    perm="$(stat -c '%a' "$resolved" 2>/dev/null || stat -f '%Lp' "$resolved" 2>/dev/null || echo "")"
  else
    perm=""
  fi
  mkdir -p "$(dirname "$resolved")"
  mv "$tmp" "$resolved"
  [ -n "$perm" ] && chmod "$perm" "$resolved"
}

strip_guarded_block() { # $1 = target file, $2 = marker line (e.g. "<!-- ways-of-working:frontier -->")
  local target="$1" marker="$2" range start end legacy resolved tmp
  [ -f "$target" ] || return 0
  [ "$(count_marker_lines "$target" "$marker")" -gt 0 ] || return 0
  range="$(guarded_block_range "$target" "$marker")"
  [ -n "$range" ] || return 0
  read -r start end legacy <<< "$range"
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] strip guarded block $marker from $target"
    return 0
  fi
  _maybe_backup_legacy "$target" "$legacy"
  resolved="$(resolve_target "$target")"
  tmp="$(mktemp "${resolved}.XXXXXX")"
  {
    if [ "$start" -gt 1 ]; then
      sed -n "1,$((start - 1))p" "$target"
    fi
    tail -n "+$((end + 1))" "$target"
  } > "$tmp"
  _finish_write "$tmp" "$resolved"
}

_copy_skill_dir_cb() { # $1 = source dir, $2 = name, $3 = dest skills dir
  # Safe-by-default like every other target: existing skill dirs are skipped
  # (users tune installed skills), --force refreshes them from the library.
  # --link installs a symlink to the library dir instead of a copy.
  local dir="$1" name="$2" dest="$3"
  if [ "$(realpath -m "$dest/$name")" = "$(realpath "${dir%/}")" ]; then
    note "skill source and destination are the same path, skipping: $dest/$name"
    return 0
  fi
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

guarded_block_replace() { # $1 = target file, $2 = begin marker line, $3 = source snippet file
  # Replaces the block bounded by the begin/end markers — or, for a legacy
  # block with no end marker, from the marker line through the line before
  # the next "<!-- ways-of-working:" marker or EOF — with the marker, the
  # current source content, and a fresh end marker. Everything before the
  # marker, and everything after the block, is left untouched.
  local target="$1" marker="$2" source="$3" range start end legacy end_marker resolved tmp
  [ -f "$target" ] || { echo "ERROR: $target not found." >&2; exit 1; }
  range="$(guarded_block_range "$target" "$marker")"
  if [ -z "$range" ]; then
    echo "ERROR: marker not found in $target: $marker" >&2
    exit 1
  fi
  read -r start end legacy <<< "$range"
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] refresh guarded block $marker in $target"
    return 0
  fi
  _maybe_backup_legacy "$target" "$legacy"
  end_marker="${marker/ways-of-working:/\/ways-of-working:}"
  resolved="$(resolve_target "$target")"
  tmp="$(mktemp "${resolved}.XXXXXX")"
  {
    if [ "$start" -gt 1 ]; then
      sed -n "1,$((start - 1))p" "$target"
    fi
    echo "$marker"
    cat "$source"
    echo "$end_marker"
    tail -n "+$((end + 1))" "$target"
  } > "$tmp"
  _finish_write "$tmp" "$resolved"
}

extract_guarded_block() { # $1 = target file, $2 = marker line; prints the block's marker+body (excludes a trailing end marker line), nothing if the marker is absent
  local target="$1" marker="$2" range start end legacy last
  [ -f "$target" ] || return 0
  range="$(guarded_block_range "$target" "$marker")"
  [ -n "$range" ] || return 0
  read -r start end legacy <<< "$range"
  if [ "$legacy" -eq 1 ]; then
    last="$end"
  else
    last=$((end - 1))
  fi
  sed -n "${start},${last}p" "$target"
}

append_guarded() { # $1 = snippet file, $2 = target file, $3 = begin marker
  local snippet="$1" target="$2" marker="$3" count suffix end_marker
  if [ -f "$target" ] && [ "$(count_marker_lines "$target" "$marker")" -eq 0 ]; then
    suffix="${marker#*:}"
    suffix="${suffix% -->}"
    if grep -qE "^<!-- [a-z0-9-]+:${suffix} -->\$" "$target"; then
      note "migrated guard marker in $target"
      if [ "$DRY_RUN" -eq 0 ]; then
        sed -i -E "s|^<!-- [a-z0-9-]+:${suffix} -->\$|${marker}|" "$target"
      else
        echo "[dry-run] migrate guard marker in $target"
      fi
      # Fall through: the marker is now present (or would be, in dry-run) —
      # the presence check below decides whether to also refresh its
      # content, in the same run, instead of requiring a second pass.
    fi
  fi

  if [ -f "$target" ] && [ "$(count_marker_lines "$target" "$marker")" -gt 0 ]; then
    count="$(count_marker_lines "$target" "$marker")"
    if [ "$count" -gt 1 ]; then
      echo "ERROR: $count copies of '$marker' found in $target; refusing to guess which to replace. Fix the file by hand." >&2
      exit 1
    fi
    if [ "$FORCE" -eq 1 ]; then
      note "refreshing guarded block (--force): $target"
      guarded_block_replace "$target" "$marker" "$snippet"
      return 0
    fi
    note "already present (marker found), skipping append: $target"
    return 0
  fi

  note "appending $(basename "$snippet") -> $target"
  if [ "$DRY_RUN" -eq 0 ]; then
    end_marker="${marker/ways-of-working:/\/ways-of-working:}"
    mkdir -p "$(dirname "$target")"
    { echo ""; echo "$marker"; cat "$snippet"; echo "$end_marker"; } >> "$target"
  else
    echo "[dry-run] append $snippet >> $target"
  fi
}

copy_md_dir() { # $1 = source subdir under $LIB (e.g. claude-md/rules, playbooks), $2 = dest dir, $3 = 1 to honor --link (default: 0 — always copy)
  # Shared by copy_rules's old job (claude-md/rules/*.md) and
  # copy_playbooks's (playbooks/*.md — ROUTING.md is referenced by name
  # from installed skills like apply-working-process, so it has to land
  # alongside them or the reference is dangling in the installed copy;
  # installing it keeps skills/ the single source of truth instead of
  # inlining the routing rule into every skill that needs it).
  #
  # A project's .claude/rules/ is never symlinked, even with --link: the
  # memory docs treat an out-of-tree symlinked rule as an external import,
  # and only its paths-less rules load until that import is approved — a
  # path-scoped rule like code-changes.md would silently stop applying.
  # --claude-user's rules and playbooks live under the user's own $HOME,
  # not a shared project, so linking them is safe and honors --link like
  # every other personal-install asset.
  local src_subdir="$1" dest="$2" allow_link="${3:-0}" f
  run mkdir -p "$dest"
  for f in "$LIB"/"$src_subdir"/*.md; do
    copy_file_safe "$f" "$dest/$(basename "$f")" "$allow_link"
  done
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
    run rm -f "$2"
    run cp "$1" "$2"
  fi
}

profile_marker_path() { echo "$1/skills/.ways-of-working-profile"; } # $1 = base (e.g. $HOME/.claude)

check_profile_marker() { # $1 = base; refuses a profile switch without --force
  local base="$1" marker installed old_suffix
  marker="$(profile_marker_path "$base")"
  if [ -f "$marker" ]; then
    installed="$(cat "$marker")"
    if [ -z "$installed" ] || ! profile_layout "$installed" >/dev/null 2>&1; then
      echo "Profile marker $marker has invalid content: '$installed'." >&2
      echo "Fix or remove it, then re-run." >&2
      exit 1
    fi
  else
    installed="$(infer_installed_profile "$base")"
    [ -n "$installed" ] || return 0 # no existing install: nothing to refuse or prune
    note "no profile marker found, but an existing install was detected; inferring profile '$installed'"
  fi
  [ "$installed" = "$PROFILE" ] && return 0
  if [ "$FORCE" -ne 1 ]; then
    echo "Installed profile is '$installed', requested '$PROFILE'." >&2
    echo "Re-run with --force to switch (this removes skills that belong only to the '$installed' pack)." >&2
    exit 1
  fi
  remove_other_profile_skills "$base" "$installed"
  read -r _ _ old_suffix _ <<< "$(require_layout "$installed" "previous profile marker")"
  strip_guarded_block "$base/CLAUDE.md" "<!-- ways-of-working:${old_suffix} -->"
}

profile_name_src() { # $1 = profile name; echoes the dir whose skill NAMES that profile owns
  # Distinct from profile_layout's SKILLS_SUBDIR (the copy/check source,
  # build/claude-code/skills for frontier): the name set a profile owns is
  # always the canonical skills/ or skills-local/ names, one-to-one with
  # the generated tree, so switching profiles never depends on the built
  # tree's contents matching — only on it existing (it's committed).
  case "$1" in
    frontier) echo "skills" ;;
    local)    echo "skills-local" ;;
    *) echo "Unknown profile: $1" >&2; return 1 ;;
  esac
}

_remove_other_profile_skill_cb() { # $1 = dir, $2 = name, $3 = base, $4 = new_names_src, $5 = other profile name
  local dir="$1" name="$2" base="$3" new_names_src="$4" other="$5"
  [ -d "$LIB/$new_names_src/$name" ] && return 0 # shared name, the new pack keeps it
  if [ -e "$base/skills/$name" ]; then
    note "removing skill from previous profile ($other), absent from $PROFILE pack: $name"
    run rm -rf "${base:?}/skills/${name:?}"
  fi
}

remove_other_profile_skills() { # $1 = base, $2 = previous profile name
  local base="$1" other="$2" other_names_src other_agents new_names_src new_agents
  other_names_src="$(profile_name_src "$other")"
  new_names_src="$(profile_name_src "$PROFILE")"
  read -r _ other_agents _ _ <<< "$(require_layout "$other" "previous profile marker")"
  read -r _ new_agents _ _ <<< "$(require_layout "$PROFILE" "requested profile")"
  for_each_skill_dir "$other_names_src" _remove_other_profile_skill_cb "$base" "$new_names_src" "$other"
  # An agents flag present on the old profile but not the new one means
  # leaving that profile removes its agents too — playbooks/ ships under
  # the same condition (frontier only), so it is removed alongside.
  if [ "$other_agents" = "agents" ] && [ "$new_agents" != "agents" ]; then
    local f name
    for f in "$LIB"/agents/*.md; do
      name="$(basename "$f")"
      if [ -e "$base/agents/$name" ]; then
        note "removing agent from previous profile ($other): $name"
        run rm -f "${base:?}/agents/${name:?}"
      fi
    done
    if [ -d "$base/playbooks" ]; then
      note "removing playbooks from previous profile ($other)"
      run rm -rf "${base:?}/playbooks"
    fi
  fi
}

write_profile_marker() { # $1 = base
  local base="$1" marker tmp
  marker="$(profile_marker_path "$base")"
  run mkdir -p "$base/skills"
  if [ "$DRY_RUN" -eq 0 ]; then
    tmp="$(mktemp "${marker}.XXXXXX")"
    echo "$PROFILE" > "$tmp"
    mv "$tmp" "$marker"
  else
    echo "[dry-run] write '$PROFILE' > $marker"
  fi
}

do_claude_user() {
  local base="$HOME/.claude" src_subdir agents_flag suffix snippet_base marker snippet
  check_profile_marker "$base"
  read -r src_subdir agents_flag suffix snippet_base <<< "$(require_layout "$PROFILE" "requested profile")"
  copy_skill_dirs "$src_subdir" "$base/skills"
  if [ "$agents_flag" = "agents" ]; then
    run mkdir -p "$base/agents"
    local f
    for f in "$LIB"/agents/*.md; do copy_file_safe "$f" "$base/agents/$(basename "$f")" 1; done
  fi
  marker="<!-- ways-of-working:${suffix} -->"
  snippet="$LIB/claude-md/${snippet_base}"
  append_guarded "$snippet" "$base/CLAUDE.md" "$marker"
  if [ "$PROFILE" = "frontier" ]; then
    copy_md_dir playbooks "$base/playbooks" 1
  fi
  copy_md_dir claude-md/rules "$base/rules" 1
  write_profile_marker "$base"
  note "done. If ~/.claude/skills was created just now, restart Claude Code once."
}

do_claude_project() {
  local proj="$ARG_CLAUDE_PROJECT" base="$ARG_CLAUDE_PROJECT/.claude"
  [ -d "$proj" ] || { echo "No such directory: $proj"; exit 1; }
  if [ "$PROFILE" = "frontier" ]; then
    copy_skill_dirs "build/claude-code/skills" "$base/skills"
    run mkdir -p "$base/agents"
    local f
    for f in "$LIB"/agents/*.md; do copy_file_safe "$f" "$base/agents/$(basename "$f")" 1; done
    copy_md_dir playbooks "$base/playbooks" 0
  else
    copy_skill_dirs "skills-local" "$base/skills"
  fi
  if [ ! -f "$proj/CLAUDE.md" ]; then
    copy_file_safe "$LIB/claude-md/project-template.md" "$proj/CLAUDE.md"
    note "created CLAUDE.md from template — fill in the marked sections."
  else
    note "CLAUDE.md exists, untouched. Template for reference: claude-md/project-template.md"
  fi
  copy_md_dir claude-md/rules "$base/rules" 0
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

# Single source of truth for the Antigravity directory names — see
# antigravity/README.md for why both exist.
ANTIGRAVITY_DIR=".agents"
ANTIGRAVITY_LEGACY_DIR=".agent"

_write_antigravity_root() { # $1 = root dir (gets rules/, workflows/, skills/)
  local root="$1" f
  run mkdir -p "$root/rules" "$root/workflows"
  for f in "$LIB"/antigravity/rules/*.md;     do copy_file_safe "$f" "$root/rules/$(basename "$f")"; done
  for f in "$LIB"/antigravity/workflows/*.md; do copy_file_safe "$f" "$root/workflows/$(basename "$f")"; done
  copy_skill_dirs "skills" "$root/skills"
}

do_antigravity() {
  local proj="$ARG_ANTIGRAVITY"
  [ -d "$proj" ] || { echo "No such directory: $proj"; exit 1; }
  _write_antigravity_root "$proj/$ANTIGRAVITY_DIR"

  local legacy="$proj/$ANTIGRAVITY_LEGACY_DIR"
  if [ ! -e "$legacy" ] || [ -L "$legacy" ]; then
    run rm -f "$legacy"
    run ln -s "$ANTIGRAVITY_DIR" "$legacy"
    note "legacy path $legacy -> $ANTIGRAVITY_DIR (symlink; see antigravity/README.md)"
  else
    note "legacy path $legacy is a real directory, writing into it too (see antigravity/README.md)"
    _write_antigravity_root "$legacy"
  fi
  note "global baseline: paste antigravity/rules/baseline.md into Antigravity's Manage Rules UI."
}

do_agents_md() {
  local proj="$ARG_AGENTS_MD"
  [ -d "$proj" ] || { echo "No such directory: $proj"; exit 1; }
  copy_file_safe "$LIB/ports/agents-md/AGENTS.md" "$proj/AGENTS.md"
  copy_skill_dirs "skills" "$proj/skills"
  note "fill in the 'Project commands' section of AGENTS.md. AGENTS.md's @skills/<name>/SKILL.md pointers resolve against $proj/skills, installed alongside it."
}

do_cursor() {
  local proj="$ARG_CURSOR"
  [ -d "$proj" ] || { echo "No such directory: $proj"; exit 1; }
  run mkdir -p "$proj/.cursor/rules"
  local f
  for f in "$LIB"/ports/cursor/*.mdc; do copy_file_safe "$f" "$proj/.cursor/rules/$(basename "$f")"; done
}

do_skills() {
  # For tools that read Agent Skills natively: Cursor (.cursor/skills),
  # the paid-tier Gemini CLI (~/.gemini/skills), Antigravity (.agents/skills).
  local dest="$ARG_SKILLS" dest_real lib_real
  dest_real="$(realpath -m "$dest")"
  lib_real="$(realpath "$LIB")"
  if [ "$dest_real" = "$lib_real/skills" ] || [[ "$dest_real" == "$lib_real"/* ]]; then
    echo "Refusing --skills $dest: it resolves inside this library ($lib_real)." >&2
    echo "Pick a destination outside the library, e.g. a project's .cursor/skills." >&2
    exit 1
  fi
  copy_skill_dirs "skills" "$dest"
  note "skills installed to $dest — Cursor: <repo>/.cursor/skills; Gemini CLI: ~/.gemini/skills; Antigravity: <repo>/.agents/skills."
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

check_claude_md_block() { # $1 = base, $2 = profile; sets DRIFT=1 and prints a DRIFT or LEGACY line as appropriate
  local base="$1" profile="$2" target suffix snippet_base marker snippet range start end legacy expected actual
  target="$base/CLAUDE.md"
  read -r _ _ suffix snippet_base <<< "$(require_layout "$profile" "--profile, marker, or inferred")"
  marker="<!-- ways-of-working:${suffix} -->"
  snippet="$LIB/claude-md/${snippet_base}"
  if [ ! -f "$target" ] || [ "$(count_marker_lines "$target" "$marker")" -eq 0 ]; then
    echo "DRIFT: CLAUDE.md block ($profile) not installed"
    DRIFT=1
    return 0
  fi
  range="$(guarded_block_range "$target" "$marker")"
  read -r start end legacy <<< "$range"
  if [ "$legacy" -eq 1 ]; then
    echo "LEGACY: CLAUDE.md block ($profile) has no end marker; run --force once"
    return 0
  fi
  expected="$(printf '%s\n' "$marker"; cat "$snippet")"
  actual="$(extract_guarded_block "$target" "$marker")"
  if [ "$expected" != "$actual" ]; then
    echo "DRIFT: CLAUDE.md block ($profile)"
    DRIFT=1
  fi
}

do_check() {
  local base="$HOME/.claude" marker="" profile src_skills agents_flag
  if [ "$PROFILE_EXPLICIT" -eq 1 ]; then
    profile="$PROFILE"
  else
    marker="$(profile_marker_path "$base")"
    if [ -f "$marker" ]; then
      profile="$(cat "$marker")"
      if [ -z "$profile" ] || ! profile_layout "$profile" >/dev/null 2>&1; then
        echo "Profile marker $marker has invalid content: '$profile'." >&2
        echo "Fix or remove it, or pass --profile explicitly, then re-run." >&2
        exit 1
      fi
    else
      profile="$(infer_installed_profile "$base")"
      [ -n "$profile" ] || profile="frontier" # nothing installed yet: default for messaging
    fi
  fi
  read -r src_skills agents_flag _ _ <<< "$(require_layout "$profile" "--profile, marker, or inferred")"
  note "checking installed skills ($profile profile) against $src_skills/ ..."

  DRIFT=0
  for_each_skill_dir "$src_skills" _check_skill_dir_cb "$base"
  check_claude_md_block "$base" "$profile"

  if [ "$agents_flag" = "agents" ]; then
    if [ ! -d "$base/agents" ]; then
      echo "DRIFT: agents not installed"
      DRIFT=1
    else
      _report_dir_diff "$LIB/agents" "$base/agents"
    fi
    # Frontier profile only: playbooks/ (see copy_md_dir) is installed
    # alongside agents/, so gate this check the same way.
    if [ ! -d "$base/playbooks" ]; then
      echo "DRIFT: playbooks not installed"
      DRIFT=1
    else
      _report_dir_diff "$LIB/playbooks" "$base/playbooks"
    fi
  elif [ -d "$base/playbooks" ]; then
    echo "DRIFT: playbooks installed under the local profile (frontier-only content)"
    DRIFT=1
  fi

  if [ ! -d "$base/rules" ]; then
    echo "DRIFT: rules not installed"
    DRIFT=1
  else
    _report_dir_diff "$LIB/claude-md/rules" "$base/rules"
  fi

  if [ "$DRIFT" -eq 1 ]; then
    echo "Drift found — see DRIFT lines above."
    exit 1
  fi
  note "no drift: installed copies match the library."
}

parse_args "$@"
for action in "${ACTIONS[@]}"; do "do_$action"; done
note "all requested installs processed."
