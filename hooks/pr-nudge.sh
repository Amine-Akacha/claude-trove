#!/usr/bin/env bash
# Stop hook: after a change that is too big to push straight to main, wake
# Claude and make it open the PR -- instead of you having to ask for one after
# an hour of work has already bloated the context.
#
# Wired with asyncRewake, so it runs in the BACKGROUND: your turn ends and you
# get the prompt back immediately. Exit 2 wakes Claude with the instructions
# below; exit 0 is silent. It never blocks you.
#
# What counts as "big" -- tune these two numbers, they are the whole policy:
BIG_FILES=2      # >= this many changed files
BIG_LINES=80     # ...or >= this many changed lines in a single file
#
# Escape hatches:
#   touch .git/claude-no-pr   -> this repo never nudges
#   PR_NUDGE_OFF=1            -> off everywhere
set -uo pipefail

[ "${PR_NUDGE_OFF:-0}" = "1" ] && exit 0

payload="$(cat)"
sid="$(printf '%s' "$payload" | jq -r '.session_id // "nosession"' 2>/dev/null)"
cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)"
[ -n "$cwd" ] && [ -d "$cwd" ] || cwd="$PWD"

g() { git -C "$cwd" "$@"; }
root="$(g rev-parse --show-toplevel 2>/dev/null)" || exit 0
[ -n "$root" ] || exit 0
gitdir="$(g rev-parse --absolute-git-dir 2>/dev/null)" || exit 0
[ -f "$gitdir/claude-no-pr" ] && exit 0

# No remote to open a PR against => nothing to do.
g remote get-url origin >/dev/null 2>&1 || exit 0

branch="$(g rev-parse --abbrev-ref HEAD 2>/dev/null)"
[ -n "$branch" ] && [ "$branch" != "HEAD" ] || exit 0   # detached: not our business

# Default branch, as the remote reports it.
default="$(g symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')"
if [ -z "$default" ]; then
  for c in main master; do
    g show-ref --verify --quiet "refs/remotes/origin/$c" && { default="$c"; break; }
  done
fi
[ -n "$default" ] || default="main"
base="origin/$default"
g show-ref --verify --quiet "refs/remotes/$base" || base=""

# ---- the change set: working tree + anything this branch has that base doesn't
tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
{
  g diff --numstat HEAD 2>/dev/null
  if [ -n "$base" ] && [ "$branch" != "$default" ]; then
    g diff --numstat "$base...HEAD" 2>/dev/null
  fi
} > "$tmp"
g ls-files --others --exclude-standard 2>/dev/null | while IFS= read -r f; do
  printf '%s\t0\t%s\n' "$(wc -l < "$root/$f" 2>/dev/null || echo 0)" "$f"
done >> "$tmp"

files=$(awk -F'\t' 'NF>=3 && $3!="" {print $3}' "$tmp" | sort -u | grep -c . || true)
lines=$(awk -F'\t' '{a=($1=="-")?0:$1; d=($2=="-")?0:$2; s+=a+d} END {print s+0}' "$tmp")
[ "${files:-0}" -eq 0 ] && exit 0

# A one-file fix or a hotpatch goes straight to main. That is the point.
if [ "$files" -lt "$BIG_FILES" ] && [ "$lines" -lt "$BIG_LINES" ]; then
  exit 0
fi

# Already landed? Feature branch, clean tree, nothing unpushed, PR open => done.
dirty=$(g status --porcelain 2>/dev/null | grep -c . || true)
if [ "$branch" != "$default" ] && [ "$dirty" -eq 0 ]; then
  unpushed=1
  if g rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' >/dev/null 2>&1; then
    unpushed=$(g log --oneline '@{upstream}..HEAD' 2>/dev/null | grep -c . || true)
  fi
  if [ "$unpushed" -eq 0 ] && command -v gh >/dev/null 2>&1; then
    open_pr="$(gh pr list --head "$branch" --state open --limit 1 --json number \
                 --jq '.[0].number' 2>/dev/null || true)"
    [ -n "$open_pr" ] && exit 0
  fi
fi

# One nudge per state per session: if nothing has changed since the last time we
# fired, stay quiet. Declining a nudge therefore ends it; more edits revive it.
fp="$sid|$branch|$(g rev-parse HEAD 2>/dev/null)|$(g status --porcelain 2>/dev/null | cksum)"
state="$gitdir/claude-pr-nudge-state"
[ -f "$state" ] && [ "$(cat "$state" 2>/dev/null)" = "$fp" ] && exit 0
printf '%s' "$fp" > "$state"

{
  echo "This change is PR-sized: $files file(s), $lines changed line(s) on '$branch'."
  echo
  echo "Open the pull request now, without waiting to be asked. Follow the prep-pr"
  echo "skill if it is available, otherwise:"
  echo "  1. If on '$default', create a branch (feat/... fix/... chore/...) and move the work to it."
  echo "  2. Verify: run this project's tests/build. Do not open a PR over a failing tree."
  echo "  3. Commit in atomic commits -- one logical change each, real messages,"
  echo "     not one 'wip' blob. Reuse the reasoning already in this session."
  echo "  4. git push -u origin <branch> && gh pr create  with a description that says"
  echo "     what changed and WHY, from what you actually did, not from the diff."
  echo "  5. Report the PR URL."
  echo
  echo "If the user has already said not to open one, or this is a deliberate hotpatch,"
  echo "say so in one line and stop -- this will not ask again for the same state."
} >&2
exit 2
