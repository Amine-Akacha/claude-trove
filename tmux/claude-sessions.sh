#!/usr/bin/env bash
# Session board: every tmux window running Claude, its state, and its PR.
#   Enter  -> jump to that session
#   Ctrl-O -> open that session's PR in the browser
# Bound to prefix + C by claude.tmux (runs in a popup).

HERE="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
# shellcheck source=../lib/platform.sh
source "$HERE/../lib/platform.sh"

rows=$(tmux list-windows -a -F \
  '#{session_name}:#{window_index}	#{@claude_state}	#{@claude_repo}	#{@claude_pr}' \
  | awk -F'\t' '$2 != ""')

if [ -z "$rows" ]; then
  echo "No Claude sessions found. (Hooks set state on first prompt.)"
  read -rn1 -p "Press any key..."
  exit 0
fi

# Sort: waiting first, then done, then working
sorted=$(printf '%s\n' "$rows" | awk -F'\t' '
  { o = ($2=="waiting") ? 0 : ($2=="done") ? 1 : 2
    icon = ($2=="waiting") ? "❗" : ($2=="done") ? "✅" : "⏳"
    pr = ($4=="") ? "-" : $4
    printf "%d\t%s\t%s %-8s\t%-35s\t%s\n", o, $1, icon, $2, $3, pr }' \
  | sort -n | cut -f2-)

if ! command -v fzf >/dev/null; then
  printf 'TARGET\tSTATE\tREPO:BRANCH\tPR\n%s\n' "$sorted" | column -t -s $'\t'
  read -rn1 -p "Install fzf for jump/open. Press any key..."
  exit 0
fi

out=$(printf '%s\n' "$sorted" | fzf --delimiter='\t' --with-nth=2.. \
  --header='Enter: jump   Ctrl-O: open PR   Esc: close' \
  --expect=ctrl-o --no-sort --reverse)

key=$(printf '%s\n' "$out" | head -1)
line=$(printf '%s\n' "$out" | sed -n 2p)
[ -z "$line" ] && exit 0

target=$(printf '%s' "$line" | cut -f1)
pr=$(printf '%s' "$line" | cut -f4)

if [ "$key" = ctrl-o ]; then
  [ "$pr" != "-" ] && open_url "$pr"
else
  tmux switch-client -t "$target"
fi
