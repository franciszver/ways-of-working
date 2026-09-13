#!/usr/bin/env bash
# check-parity.sh — compare the canonical skill name set (skills/*/SKILL.md)
# against every port. Prints missing names per surface and exits 1 if any
# canonical skill is missing from a surface, unless the gap is allowlisted
# in scripts/parity-allow.txt.
#
# Usage: scripts/check-parity.sh

set -euo pipefail

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

exec python3 "$LIB/scripts/check_parity.py" "$LIB"
