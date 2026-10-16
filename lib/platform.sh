#!/usr/bin/env bash
# Platform helpers, sourced by the tmux scripts. WSL, macOS and desktop Linux
# each have their own way to open a URL and raise a desktop notification.
#
#   open_url <url>
#   notify <title> <message>     returns immediately; never fails the caller

is_wsl() { [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qi microsoft /proc/version 2>/dev/null; }

open_url() {
  if command -v wslview >/dev/null; then wslview "$1"
  # explorer.exe exits 1 even on success, so its status is ignored.
  elif is_wsl && command -v explorer.exe >/dev/null; then explorer.exe "$1" || true
  elif [ "$(uname -s)" = Darwin ]; then open "$1"
  elif command -v xdg-open >/dev/null; then xdg-open "$1" >/dev/null 2>&1
  else echo "$1"; read -rn1 -p "Press any key..."; fi
}

# Windows toast via the built-in WinRT API (no modules needed). Single quotes are
# stripped because the text is embedded in single-quoted PowerShell strings.
_toast_windows() {
  local title="${1//\'/}" text="${2//\'/}"
  powershell.exe -NoProfile -NonInteractive -Command "
    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] > \$null
    \$t = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
    \$x = \$t.GetElementsByTagName('text')
    \$x.Item(0).AppendChild(\$t.CreateTextNode('$title')) > \$null
    \$x.Item(1).AppendChild(\$t.CreateTextNode('$text')) > \$null
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe').Show([Windows.UI.Notifications.ToastNotification]::new(\$t))
  "
}

# Detached: powershell.exe alone takes about a second to start.
notify() {
  local title="$1" text="$2"
  [ "${CLAUDE_NOTIFY:-1}" = 0 ] && return 0
  if is_wsl && command -v powershell.exe >/dev/null; then
    ( _toast_windows "$title" "$text" ) >/dev/null 2>&1 &
  elif [ "$(uname -s)" = Darwin ]; then
    osascript -e "display notification \"${text//\"/}\" with title \"${title//\"/}\"" >/dev/null 2>&1 &
  elif command -v notify-send >/dev/null; then
    notify-send "$title" "$text" >/dev/null 2>&1 &
  fi
  return 0
}
