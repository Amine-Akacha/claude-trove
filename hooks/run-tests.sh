#!/usr/bin/env bash
# Stop hook: run this project's verification command once the turn is over.
#
# Wired with asyncRewake, so it runs in the BACKGROUND -- your turn ends
# immediately and you get the prompt back. Exit 2 wakes Claude with the
# failure output; exit 0 is silent. It never blocks you either way.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=detect-stack.sh
source "$HERE/detect-stack.sh" 2>/dev/null || exit 0
[ -n "${TEST_CMD:-}" ] || exit 0

# Nothing changed => nothing to verify.
if git -C "$PROJ_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$PROJ_ROOT" status --porcelain 2>/dev/null | grep -q . || exit 0
fi

out="$(cd "$PROJ_ROOT" && eval "$TEST_CMD" 2>&1)"
code=$?
[ "$code" -eq 0 ] && exit 0

{
  echo "Verification failed after your changes."
  echo "Command: $TEST_CMD   (in $PROJ_ROOT)"
  echo "--- last 40 lines ---"
  printf '%s\n' "$out" | tail -40
} >&2
exit 2
