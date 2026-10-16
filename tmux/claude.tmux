# Claude Code + tmux, installed by claude-trove. Source it from ~/.tmux.conf:
#   source-file -q ~/.claude/claude.tmux
#
# Window state (⏳ working / ✅ done / ❗ waiting) is set by the hooks in
# settings/tmux.json. Optional theming, in your own tmux.conf:
#   status-right:  #(~/.claude/bin/claude-tmux-counts.sh)   -> ❗2 ✅1
#   set -g @claude-waiting-style 'fg=#c4746e,bold'
#   set -g @claude-done-style    'fg=#87a987'
#   window-status-format: #{?#{==:#{@claude_state},waiting},#[fg=red],}  -> red waiting windows

bind C display-popup -E -w 90% -h 60% "~/.claude/bin/claude-sessions.sh"   # session board
bind P display-popup -E -w 90% -h 60% "~/.claude/bin/claude-prs.sh"        # your open PRs
