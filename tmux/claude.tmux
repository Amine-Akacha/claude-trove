# Claude Code + tmux, installed by claude-trove. Source it from ~/.tmux.conf:
#   source-file -q ~/.claude/claude.tmux
#
# Different keys? Set these BEFORE the source-file line (defaults: C and P):
#   set -g @claude-board-key 'C'
#   set -g @claude-prs-key   'P'
#
# Window state (⏳ working / ✅ done / ❗ waiting) is set by the hooks in
# settings/tmux.json. Optional theming, in your own tmux.conf (docs/tmux.md has
# a full snippet):
#   status-right:  #(~/.claude/bin/claude-tmux-counts.sh)   -> ❗2 ✅1
#   set -g @claude-waiting-style 'fg=#c4746e,bold'
#   set -g @claude-done-style    'fg=#87a987'
#   window-status-format: #{?#{==:#{@claude_state},waiting},#[fg=red],}  -> red waiting windows

# session board
run-shell 'k=$(tmux show -gqv @claude-board-key); tmux bind-key "${k:-C}" display-popup -E -w 90% -h 60% "$HOME/.claude/bin/claude-sessions.sh"'
# your open PRs
run-shell 'k=$(tmux show -gqv @claude-prs-key); tmux bind-key "${k:-P}" display-popup -E -w 90% -h 60% "$HOME/.claude/bin/claude-prs.sh"'
