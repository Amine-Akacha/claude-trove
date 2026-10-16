#!/usr/bin/env bash
# Called by Claude Code hooks. Usage: claude-tmux-status.sh <working|done|waiting>
# Inside tmux: renames the window to show state + repo:branch and remembers the
# PR url for the session board. Anywhere: a desktop notification when a session
# finishes or needs input (CLAUDE_NOTIFY=0 turns that off).

HERE="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
# shellcheck source=../lib/platform.sh
source "$HERE/../lib/platform.sh"

state="$1"
input="$(cat)"                      # hook JSON arrives on stdin

case "$state" in
  working) icon="⏳" ;;
  done)    icon="✅" ;;
  waiting) icon="❗" ;;
  *)       exit 0 ;;
esac

# PostToolUse fires this after every tool call; outside tmux there is nothing to do for it.
[ "$state" = working ] && [ -z "$TMUX_PANE" ] && exit 0

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$cwd" ] && cwd="$PWD"

root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || echo "$cwd")
repo=$(basename "$root")
branch=$(git -C "$cwd" branch --show-current 2>/dev/null)

if [ -n "$TMUX_PANE" ]; then
  label="$icon $repo"
  [ -n "$branch" ] && label="$label:$branch"

  win=$(tmux display-message -p -t "$TMUX_PANE" '#{window_id}')
  tmux set-option -w -t "$win" automatic-rename off
  tmux rename-window -t "$win" "$label"
  tmux set-option -w -t "$win" @claude_state "$state"
  tmux set-option -w -t "$win" @claude_repo "$repo:$branch"
fi

# Skip notifications and gh lookups while working
[ "$state" = working ] && exit 0

# Look up the PR for this branch in the background so the hook returns instantly
if [ -n "$TMUX_PANE" ] && [ -n "$branch" ] && command -v gh >/dev/null; then
  (
    pr=$(cd "$cwd" && gh pr view --json url --jq .url 2>/dev/null)
    [ -n "$pr" ] && tmux set-option -w -t "$win" @claude_pr "$pr"
  ) >/dev/null 2>&1 &
fi

if [ "$state" = done ]; then msg="$repo finished"; else msg="$repo needs you"; fi

[ -n "$TMUX_PANE" ] && tmux display-message -d 4000 "Claude: $msg"
notify "Claude Code" "$msg"

exit 0
