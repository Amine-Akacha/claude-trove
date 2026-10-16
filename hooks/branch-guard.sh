#!/usr/bin/env bash
# PreToolUse hook (Write|Edit): the first time Claude edits a tracked file while
# sitting on the default branch, say so.
#
# Advisory only -- it never blocks the edit, because a one-file hotpatch on main
# is a legitimate thing to do. It exists so the branch gets made BEFORE an hour
# of work lands as one lump on main, which is the expensive way to find out.
# Fires at most once per session per repo.
set -uo pipefail

payload="$(cat)"
file="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
sid="$(printf '%s' "$payload" | jq -r '.session_id // "nosession"' 2>/dev/null)"
[ -n "$file" ] || exit 0

dir="$(dirname "$file")"
[ -d "$dir" ] || exit 0
g() { git -C "$dir" "$@"; }

gitdir="$(g rev-parse --absolute-git-dir 2>/dev/null)" || exit 0
[ -n "$gitdir" ] || exit 0
g remote get-url origin >/dev/null 2>&1 || exit 0

branch="$(g rev-parse --abbrev-ref HEAD 2>/dev/null)"
default="$(g symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')"
if [ -z "$default" ]; then
  for c in main master; do
    g show-ref --verify --quiet "refs/remotes/origin/$c" && { default="$c"; break; }
  done
fi
[ "$branch" = "${default:-main}" ] || exit 0

# New, untracked files are usually scaffolding; only warn on real edits.
g ls-files --error-unmatch "$file" >/dev/null 2>&1 || exit 0

marker="${TMPDIR:-/tmp}/claude-branch-guard-$(id -u)-$sid-$(printf '%s' "$gitdir" | cksum | cut -d' ' -f1)"
[ -f "$marker" ] && exit 0
: > "$marker"

msg="On '$branch' with a remote. Fine for a one-file fix or hotpatch. If this is a feature, a refactor, or anything spanning several files, branch first (git checkout -b feat/...) so the work can go up as a clean PR instead of being untangled from main later."
jq -n --arg m "$msg" '{
  systemMessage: $m,
  hookSpecificOutput: { hookEventName: "PreToolUse", additionalContext: $m }
}'
exit 0
