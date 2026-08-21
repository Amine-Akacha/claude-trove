#!/usr/bin/env bash
# PostToolUse hook (Write|Edit): format + autofix the single file that changed.
# Never blocks and never fails the tool call -- worst case it does nothing.
set -uo pipefail

# Resolve our own directory BEFORE cd'ing anywhere.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

payload="$(cat)"
file="$(printf '%s' "$payload" | jq -r '.tool_response.filePath // .tool_input.file_path // empty' 2>/dev/null)"
[ -n "$file" ] && [ -f "$file" ] || exit 0

# Skip what a code formatter has no business touching.
case "$file" in
  *.md|*.json|*.lock|*.txt|*.csv|*.svg|*.png|*.jpg|*.jpeg|*.pdf|*.ipynb) exit 0 ;;
esac

cd "$(dirname "$file")" 2>/dev/null || exit 0
# shellcheck source=detect-stack.sh
source "$HERE/detect-stack.sh" 2>/dev/null || exit 0
[ -n "${LINT_CMD:-}" ] || exit 0

cmd="${LINT_CMD//\{\}/$file}"
( cd "$PROJ_ROOT" && eval "$cmd" ) >/dev/null 2>&1 || true
exit 0
