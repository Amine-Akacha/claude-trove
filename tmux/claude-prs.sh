#!/usr/bin/env bash
# All your open PRs across every repo, including ones from sessions you closed.
#   Enter -> open in browser
# Bound to prefix + P by claude.tmux.

HERE="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
# shellcheck source=../lib/platform.sh
source "$HERE/../lib/platform.sh"

prs=$(gh search prs --author @me --state open --limit 50 \
  --json repository,number,title,url,isDraft,updatedAt \
  --jq 'sort_by(.updatedAt) | reverse | .[] |
        "\(.repository.name)#\(.number)\t\(if .isDraft then "draft" else "open " end)\t\(.title)\t\(.url)"' 2>&1)

if [ $? -ne 0 ] || [ -z "$prs" ]; then
  echo "${prs:-No open PRs.}"
  read -rn1 -p "Press any key..."
  exit 0
fi

if ! command -v fzf >/dev/null; then
  printf '%s\n' "$prs" | column -t -s $'\t'
  read -rn1 -p "Press any key..."
  exit 0
fi

url=$(printf '%s\n' "$prs" | fzf --delimiter='\t' --with-nth=1..3 \
  --header='Enter: open PR   Esc: close' --reverse | cut -f4)

[ -n "$url" ] && open_url "$url"
