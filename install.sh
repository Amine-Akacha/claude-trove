#!/usr/bin/env bash
# Install this trove into ~/.claude.
#
#   ./install.sh            symlink skills, merge settings (hooks + permissions)
#   ./install.sh --skills   skills only, leave settings.json alone
#   ./install.sh --dry-run  show what would change, touch nothing
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CLAUDE_DIR/settings.json"

SKILLS_ONLY=0; DRY=0
for arg in "$@"; do
  case "$arg" in
    --skills)  SKILLS_ONLY=1 ;;
    --dry-run) DRY=1 ;;
    -h|--help) sed -n '2,7p' "$0"; exit 0 ;;
    *) echo "unknown flag: $arg" >&2; exit 1 ;;
  esac
done

command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

say() { [ "$DRY" -eq 1 ] && echo "[dry-run] $*" || echo "$*"; }
run() { [ "$DRY" -eq 1 ] || eval "$@"; }

# --- skills ---------------------------------------------------------------
mkdir -p "$CLAUDE_DIR/skills"
for skill in "$REPO"/skills/*/; do
  name="$(basename "$skill")"
  target="$CLAUDE_DIR/skills/$name"
  if [ -e "$target" ] && [ ! -L "$target" ]; then
    echo "SKIP  $name — $target exists and is not a symlink (move it aside first)"
    continue
  fi
  say "LINK  $name -> $target"
  run "ln -sfn '$skill' '$target'"
done

# --- hooks executable -----------------------------------------------------
run "chmod +x '$REPO'/hooks/*.sh"

[ "$SKILLS_ONLY" -eq 1 ] && { echo; echo "Skills only. Settings untouched."; exit 0; }

# --- settings -------------------------------------------------------------
# Merge, never replace: existing keys win for scalars, arrays are unioned.
[ -f "$SETTINGS" ] || run "echo '{}' > '$SETTINGS'"

if [ -f "$SETTINGS" ] && ! jq -e . "$SETTINGS" >/dev/null 2>&1; then
  echo "ABORT $SETTINGS is not valid JSON — fix it first, a broken settings file disables ALL settings." >&2
  exit 1
fi

backup="$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"
say "BACKUP $SETTINGS -> $backup"
run "cp '$SETTINGS' '$backup'"

incoming="$(sed "s|__TROVE__|$REPO|g" "$REPO/settings/settings.json")"

merged="$(jq -n --argjson cur "$(cat "$SETTINGS")" --argjson new "$incoming" '
  def uniq_cat($a; $b): (($a // []) + ($b // [])) | unique;
  $cur
  # hooks: drop any previous trove hooks, then append the current ones,
  # so re-running the installer never stacks duplicates.
  | .hooks.PostToolUse = (
      [ (($cur.hooks.PostToolUse // [])[]
         | select([ .hooks[]?.command? // "" | test("/hooks/lint-file\\.sh$") ] | any | not)) ]
      + ($new.hooks.PostToolUse // []) )
  | .hooks.Stop = (
      [ (($cur.hooks.Stop // [])[]
         | select([ .hooks[]?.command? // "" | test("/hooks/run-tests\\.sh$") ] | any | not)) ]
      + ($new.hooks.Stop // []) )
  | .permissions.allow = uniq_cat($cur.permissions.allow; $new.permissions.allow)
  | .permissions.deny  = uniq_cat($cur.permissions.deny;  $new.permissions.deny)
')"

if [ "$DRY" -eq 1 ]; then
  echo "[dry-run] settings.json would become:"
  printf '%s\n' "$merged" | jq .
else
  printf '%s\n' "$merged" | jq . > "$SETTINGS"
  echo "MERGE $SETTINGS (hooks + permissions)"
fi

echo
echo "Done."
echo "  Skills:      $(ls "$REPO"/skills | tr '\n' ' ')"
echo "  Hooks:       lint-on-edit (PostToolUse), tests-on-stop (Stop, background)"
echo "  Backup:      $backup"
echo
echo "Open /hooks once, or restart Claude Code, for the hooks to load."
