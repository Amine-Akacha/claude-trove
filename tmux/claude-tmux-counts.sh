#!/usr/bin/env bash
# tmux status segment: how many Claude sessions are waiting on you / done.
# Prints nothing when there are none. Use it in status-right:
#   #(~/.claude/bin/claude-tmux-counts.sh)
# Colors come from the @claude-waiting-style / @claude-done-style tmux options.

wait_style=$(tmux show-option -gqv @claude-waiting-style); : "${wait_style:=fg=red,bold}"
done_style=$(tmux show-option -gqv @claude-done-style);    : "${done_style:=fg=green}"

tmux list-windows -a -F '#{@claude_state}' | awk -v ws="$wait_style" -v ds="$done_style" '
  /waiting/ { w++ } /done/ { d++ }
  END {
    if (w) printf "#[%s]❗%d #[default]", ws, w
    if (d) printf "#[%s]✅%d #[default]", ds, d
  }'
