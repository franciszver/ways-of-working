#!/usr/bin/env bash
# Stop hook. Formats files changed in the working tree using whatever formatter
# the project is configured for. Detection is by config file; silent no-op when
# nothing is detected. ALWAYS exits 0 — formatting must never block the session.
set -u

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$PROJECT_DIR" 2>/dev/null || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# Changed + untracked files, NUL-safe
CHANGED="$(
  { git diff --name-only HEAD 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null; } | sort -u
)"
[ -n "$CHANGED" ] || exit 0

filter_ext() { printf '%s\n' "$CHANGED" | grep -E "$1" || true; }

# Prettier — if the project configures it
if [ -f .prettierrc ] || [ -f .prettierrc.json ] || [ -f .prettierrc.yaml ] || [ -f .prettierrc.yml ] || [ -f .prettierrc.js ] || [ -f prettier.config.js ] || { [ -f package.json ] && grep -q '"prettier"' package.json 2>/dev/null; }; then
  FILES="$(filter_ext '\.(js|jsx|ts|tsx|css|scss|json|md|html|yml|yaml)$')"
  if [ -n "$FILES" ] && command -v npx >/dev/null 2>&1; then
    printf '%s\n' "$FILES" | tr '\n' '\0' | xargs -0 -r npx --no-install prettier --write >/dev/null 2>&1 || true
  fi
fi

# Python — ruff format preferred, else black; only if configured in pyproject.toml
if [ -f pyproject.toml ]; then
  PYFILES="$(filter_ext '\.py$')"
  if [ -n "$PYFILES" ]; then
    if grep -q '\[tool\.ruff' pyproject.toml 2>/dev/null && command -v ruff >/dev/null 2>&1; then
      printf '%s\n' "$PYFILES" | tr '\n' '\0' | xargs -0 -r ruff format >/dev/null 2>&1 || true
    elif grep -q '\[tool\.black\]' pyproject.toml 2>/dev/null && command -v black >/dev/null 2>&1; then
      printf '%s\n' "$PYFILES" | tr '\n' '\0' | xargs -0 -r black -q >/dev/null 2>&1 || true
    fi
  fi
fi

# Go
GOFILES="$(filter_ext '\.go$')"
if [ -n "$GOFILES" ] && command -v gofmt >/dev/null 2>&1; then
  printf '%s\n' "$GOFILES" | tr '\n' '\0' | xargs -0 -r gofmt -w >/dev/null 2>&1 || true
fi

# Rust
if [ -f Cargo.toml ] && [ -n "$(filter_ext '\.rs$')" ] && command -v cargo >/dev/null 2>&1; then
  cargo fmt >/dev/null 2>&1 || true
fi

exit 0
