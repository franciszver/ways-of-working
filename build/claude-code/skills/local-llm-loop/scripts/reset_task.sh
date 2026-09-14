#!/usr/bin/env bash
# Build a fresh runtime work copy of the bundled taskrepo test fixture
# from its tracked, pristine sources at fixtures/taskrepo-src/. Used
# only by test_loop.sh — not part of the loop driver itself.
#
# Usage: reset_task.sh [--dest <path>]
#   --dest   Where to build the work copy (default: /tmp/local-llm-loop/taskrepo).
#
# Safe to run repeatedly: it always removes any existing dest first,
# copies the pristine sources in, then git-inits and commits a "clean
# state" baseline so an agent under test sees a normal repo with no
# pending changes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/fixtures/taskrepo-src"

DEST="/tmp/local-llm-loop/taskrepo"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dest)
            DEST="$2"
            shift 2
            ;;
        *)
            echo "reset_task.sh: unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

if [[ ! -d "$SRC_DIR" ]]; then
    echo "reset_task.sh: missing fixture sources: $SRC_DIR" >&2
    exit 1
fi

# Guard the rm -rf below: refuse to run it against anything that isn't
# clearly a disposable taskrepo work copy. --dest is caller-supplied, so
# a typo or a bad path (e.g. an empty string, or "/") must not reach
# rm -rf. Require the resolved destination to contain the literal path
# segment "taskrepo" — the shape every legitimate --dest actually takes.
case "$DEST" in
    /*) DEST_ABS="$DEST" ;;
    *) DEST_ABS="$(pwd)/$DEST" ;;
esac
DEST_ABS="$(realpath -m -- "$DEST_ABS")"
case "$DEST_ABS" in
    */taskrepo|*/taskrepo/*) ;;
    *)
        echo "reset_task.sh: refusing to rm -rf '$DEST_ABS' -- it does not contain the path segment 'taskrepo'" >&2
        exit 1
        ;;
esac

rm -rf "$DEST_ABS"
DEST="$DEST_ABS"
mkdir -p "$(dirname "$DEST")"
cp -a "$SRC_DIR" "$DEST"
find "$DEST" -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null || true

git -C "$DEST" init -q
git -C "$DEST" add -A
git -C "$DEST" -c user.email=bench@local -c user.name=bench commit -qm "clean state"

echo "reset_task.sh: work copy ready at $DEST"
