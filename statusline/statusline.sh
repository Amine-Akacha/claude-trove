#!/usr/bin/env bash
# Claude Code status line. Claude pipes session JSON on stdin; we print one line:
#
#   Opus 5.5 high │ ██████░░░░ 62% 124k/200k │ $1.37 │ 5h 22% · 7d 8% │ 12m │ +120 −34 │ repo ⎇ branch │ PR #3
#
# model+effort │ context window │ session cost │ plan usage │ duration │ lines │ git │ PR
#
# Cost is what the session would cost at API prices. On a Pro/Max subscription
# you are not billed that; the 5h/7d plan usage is the number that matters.
# Everything is read locally from stdin + git -- no network calls.
set -uo pipefail

IFS=$'\x1f' read -r model effort used_tok win_size used_pct cost dur_ms added removed \
  five_h seven_d dir pr_num pr_state < <(jq -r '[
    .model.display_name // "?",
    .effort.level // "",
    .context_window.total_input_tokens // 0,
    .context_window.context_window_size // 0,
    .context_window.used_percentage // "",
    .cost.total_cost_usd // 0,
    .cost.total_duration_ms // 0,
    .cost.total_lines_added // 0,
    .cost.total_lines_removed // 0,
    .rate_limits.five_hour.used_percentage // "",
    .rate_limits.seven_day.used_percentage // "",
    .workspace.current_dir // .cwd // "",
    .pr.number // "",
    .pr.review_state // ""
  ] | map(tostring) | join("\u001f")')

# Colors: dim separators, and green/yellow/red by how close a gauge is to full.
R=$'\e[0m'; DIM=$'\e[2m'; BOLD=$'\e[1m'
GREEN=$'\e[32m'; YELLOW=$'\e[33m'; RED=$'\e[31m'; BLUE=$'\e[34m'; MAGENTA=$'\e[35m'; CYAN=$'\e[36m'
SEP=" ${DIM}│${R} "

level() {  # level <percent> -> color escape
  local p=${1%.*}; p=${p:-0}
  if   [ "$p" -ge 80 ]; then printf '%s' "$RED"
  elif [ "$p" -ge 50 ]; then printf '%s' "$YELLOW"
  else printf '%s' "$GREEN"; fi
}

human() {  # human <tokens> -> 950 / 12k / 1.2M
  awk -v n="$1" 'BEGIN {
    if (n >= 1000000) printf "%.1fM", n/1000000
    else if (n >= 1000) printf "%dk", n/1000
    else printf "%d", n }'
}

out="${BOLD}${model}${R}"
[ -n "$effort" ] && out+=" ${DIM}${effort}${R}"

# Context window
if [ -n "$used_pct" ]; then
  pct=${used_pct%.*}
  filled=$(( (pct + 5) / 10 )); [ "$filled" -gt 10 ] && filled=10
  bar=""; for i in 1 2 3 4 5 6 7 8 9 10; do   # not tr: it mangles multibyte chars
    if [ "$i" -le "$filled" ]; then bar+="█"; else bar+="░"; fi
  done
  c=$(level "$pct")
  out+="${SEP}${c}${bar} ${pct}%${R} ${DIM}$(human "$used_tok")/$(human "$win_size")${R}"
else
  out+="${SEP}${DIM}ctx --${R}"
fi

# Session cost (API-equivalent)
out+="${SEP}${CYAN}\$$(printf '%.2f' "$cost")${R}"

# Plan usage, only reported for subscription logins
if [ -n "$five_h" ] || [ -n "$seven_d" ]; then
  usage=""
  [ -n "$five_h" ]  && usage+="$(level "$five_h")5h ${five_h%.*}%${R}"
  [ -n "$five_h" ] && [ -n "$seven_d" ] && usage+=" ${DIM}·${R} "
  [ -n "$seven_d" ] && usage+="$(level "$seven_d")7d ${seven_d%.*}%${R}"
  out+="${SEP}${usage}"
fi

# Duration
mins=$(( dur_ms / 60000 ))
if [ "$mins" -ge 60 ]; then dur="$((mins / 60))h$((mins % 60))m"; else dur="${mins}m"; fi
out+="${SEP}${DIM}${dur}${R}"

# Lines changed
if [ "$added" != 0 ] || [ "$removed" != 0 ]; then
  out+="${SEP}${GREEN}+${added}${R} ${RED}−${removed}${R}"
fi

# Git
if [ -n "$dir" ]; then
  root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)
  name=$(basename "${root:-$dir}")
  branch=$(git -C "$dir" branch --show-current 2>/dev/null)
  git_part="${BLUE}${name}${R}"
  if [ -n "$branch" ]; then
    dirty=""
    [ -n "$(git -C "$dir" status --porcelain --untracked-files=no 2>/dev/null | head -1)" ] && dirty="${YELLOW}*${R}"
    git_part+=" ${MAGENTA}⎇ ${branch}${R}${dirty}"
  fi
  out+="${SEP}${git_part}"
fi

# PR, when Claude Code knows of one for this branch
if [ -n "$pr_num" ]; then
  pr="PR #${pr_num}"
  [ -n "$pr_state" ] && pr+=" ${DIM}${pr_state}${R}"
  out+="${SEP}${pr}"
fi

printf '%s\n' "$out"
