#!/usr/bin/env bash
# Install this trove into ~/.claude. Pick the modules you want.
#
#   ./install.sh                     the default modules (see --list)
#   ./install.sh statusline tmux     only these modules
#   ./install.sh --all               every module, opt-in ones included
#   ./install.sh --list              show the modules
#   ./install.sh --dry-run [...]     show what would change, touch nothing
#
# Re-running is safe: skills are symlinks, settings are merged (your keys survive,
# arrays are unioned, a module's hooks replace its previous copy instead of stacking).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CLAUDE_DIR/settings.json"

# name|default|description
MODULES="
skills|on|Workflow skills: /audit /ship-fix /prep-pr /i-have-adhd
core|on|Hooks: format on edit, background tests on stop, branch warning on main + safe permissions
statusline|on|Status line: model, context window, cost, plan usage, git branch, PR
tmux|on|tmux session board (prefix+C), open PRs (prefix+P), window state + desktop notifications
pr-nudge|off|Stop hook that has Claude open a PR once a change gets big
task|off|/task skill for taskwarrior + bugwarrior (needs both installed)
"
# Skills owned by an opt-in module; the skills module leaves them alone.
OPTIN_SKILLS="task"

list_modules() {
  printf '%s\n' "$MODULES" | awk -F'|' 'NF==3 { printf "  %-11s %-4s %s\n", $1, ($2=="on" ? "*" : ""), $3 }'
  echo; echo "  * = installed by default"
}

usage() { sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; echo; list_modules; }

DRY=0; ALL=0; picked=()
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY=1 ;;
    --all)     ALL=1 ;;
    --skills)  picked+=(skills) ;;   # kept for older docs
    --list)    list_modules; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    -*)        echo "unknown flag: $arg" >&2; exit 1 ;;
    *)
      printf '%s\n' "$MODULES" | cut -d'|' -f1 | grep -qx "$arg" \
        || { echo "unknown module: $arg (see --list)" >&2; exit 1; }
      picked+=("$arg") ;;
  esac
done

if [ "$ALL" -eq 1 ]; then
  mapfile -t picked < <(printf '%s\n' "$MODULES" | awk -F'|' 'NF==3 {print $1}')
elif [ "${#picked[@]}" -eq 0 ]; then
  mapfile -t picked < <(printf '%s\n' "$MODULES" | awk -F'|' 'NF==3 && $2=="on" {print $1}')
fi
want() { printf '%s\n' "${picked[@]}" | grep -qx "$1"; }

command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

say() { [ "$DRY" -eq 1 ] && echo "[dry-run] $*" || echo "$*"; }
run() { [ "$DRY" -eq 1 ] || "$@"; }

# link <source> <target>: symlink, but never clobber a real file
link() {
  local src="$1" dst="$2"
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    echo "SKIP  $dst exists and is not a symlink (move it aside first)"
    return 0
  fi
  say "LINK  $dst -> $src"
  run ln -sfn "$src" "$dst"
}

echo "Modules: ${picked[*]}"
echo
run mkdir -p "$CLAUDE_DIR/skills"
run chmod +x "$REPO"/hooks/*.sh "$REPO"/tmux/*.sh "$REPO"/statusline/*.sh

# --- skills ---------------------------------------------------------------
if want skills; then
  for skill in "$REPO"/skills/*/; do
    name="$(basename "$skill")"
    [[ " $OPTIN_SKILLS " == *" $name "* ]] && continue
    link "${skill%/}" "$CLAUDE_DIR/skills/$name"
  done
fi
want task && link "$REPO/skills/task" "$CLAUDE_DIR/skills/task"

# --- tmux: scripts at a stable path for tmux.conf -------------------------
if want tmux; then
  if [ -L "$CLAUDE_DIR/bin" ]; then
    echo "SKIP  tmux scripts: $CLAUDE_DIR/bin is a symlink to $(readlink "$CLAUDE_DIR/bin")."
    echo "      Remove it (or unstow the dotfiles package that owns it) and re-run."
  else
    run mkdir -p "$CLAUDE_DIR/bin"
    for s in "$REPO"/tmux/*.sh; do link "$s" "$CLAUDE_DIR/bin/$(basename "$s")"; done
    link "$REPO/tmux/claude.tmux" "$CLAUDE_DIR/claude.tmux"
  fi
fi

# --- settings -------------------------------------------------------------
fragments=()
for m in core statusline tmux pr-nudge; do
  want "$m" && fragments+=("$REPO/settings/$m.json")
done

if [ "${#fragments[@]}" -gt 0 ]; then
  [ -f "$SETTINGS" ] || run sh -c "echo '{}' > '$SETTINGS'"
  current='{}'
  if [ -f "$SETTINGS" ]; then
    jq -e . "$SETTINGS" >/dev/null 2>&1 || {
      echo "ABORT $SETTINGS is not valid JSON — fix it first, a broken settings file disables ALL settings." >&2
      exit 1
    }
    current="$(cat "$SETTINGS")"
  fi

  # Don't replace a status line the user wrote themselves.
  existing_sl="$(printf '%s' "$current" | jq -r '.statusLine.command // empty')"
  keep_sl=0
  if want statusline && [ -n "$existing_sl" ] && [[ "$existing_sl" != *statusline/statusline.sh* ]]; then
    echo "SKIP  statusLine: you already have one ($existing_sl). Remove it from $SETTINGS to use the trove's."
    keep_sl=1
  fi

  merged="$current"
  for f in "${fragments[@]}"; do
    incoming="$(sed "s|__TROVE__|$REPO|g" "$f")"
    merged="$(jq -n --argjson cur "$merged" --argjson new "$incoming" --argjson keep_sl "$keep_sl" '
      def uniq_cat($a; $b): (($a // []) + ($b // [])) | unique;
      # A hook is identified by the script it runs, wherever it lives, so a
      # re-install (or an old copy at another path) is replaced, not stacked.
      def script: split(" ")[0] | split("/") | last;
      def scripts: [ .hooks[]?.command? // "" | script ];
      reduce (($new.hooks // {}) | to_entries[]) as $e ($cur;
        ([ $e.value[] | scripts[] ]) as $mine
        | .hooks[$e.key] = (
            [ (.hooks[$e.key] // [])[] | select((scripts - $mine) == scripts) ]
            + $e.value ))
      | if $new.permissions then
          .permissions.allow = uniq_cat(.permissions.allow; $new.permissions.allow)
          | .permissions.deny = uniq_cat(.permissions.deny; $new.permissions.deny)
        else . end
      | if $new.statusLine and ($keep_sl == 0) then .statusLine = $new.statusLine else . end
    ')"
  done

  if [ "$DRY" -eq 1 ]; then
    echo "[dry-run] settings.json would change like this:"
    diff <(printf '%s' "$current" | jq -S .) <(printf '%s' "$merged" | jq -S .) || true
  else
    backup="$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"
    cp "$SETTINGS" "$backup"
    printf '%s\n' "$merged" | jq . > "$SETTINGS"
    echo "MERGE $SETTINGS (backup: $backup)"
  fi
fi

echo
echo "Done. Restart Claude Code (or open /hooks once) to load hook changes."
if want tmux; then
  echo "tmux: add this line to ~/.tmux.conf, then prefix+r or restart tmux:"
  echo "        source-file -q ~/.claude/claude.tmux"
fi
