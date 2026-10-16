# Claude Code in tmux: setup guide

Run several Claude Code sessions in tmux and always know which one needs you.

- Each Claude window is renamed `⏳ repo:branch` while it works, `✅` when it's
  done, and `❗` when it's waiting on you (a permission prompt or a question).
- You get a desktop notification when a session finishes or needs input: a
  Windows toast on WSL, Notification Center on macOS, `notify-send` on Linux.
- `prefix + C` opens a **session board**: every Claude window, waiting ones
  first. `Enter` jumps there, `Ctrl-O` opens its PR.
- `prefix + P` lists **all your open PRs** across repos. `Enter` opens one in
  the browser.

This works with your own tmux config. You add one line to it, and nothing else
in it changes.

## What you need

| Tool | Why | Check |
|---|---|---|
| Linux, macOS or WSL2 | | |
| [Claude Code](https://docs.claude.com/en/docs/claude-code) | | `claude --version` |
| tmux 3.2+ | popups (`display-popup`) | `tmux -V` |
| `jq` | the installer merges settings with it, the hooks parse with it | `jq --version` |
| `git` | repo and branch names | |
| `fzf` | jump / open in the popups (without it you get a plain table) | `fzf --version` |
| [`gh`](https://cli.github.com), logged in | PR lookups for the board and `prefix + P` | `gh auth status` |

Install the missing ones with your package manager, e.g.
`sudo apt install jq fzf gh` or `brew install jq fzf gh`, then `gh auth login`.

On WSL, `wslu` (for `wslview`) is optional: links fall back to `explorer.exe`.

## 1. Install

```bash
git clone https://github.com/FucciUnavailable/claude-trove.git ~/repos/claude-trove
cd ~/repos/claude-trove
./install.sh --dry-run tmux statusline    # see what it will change first
./install.sh tmux statusline
```

`statusline` is the line under Claude Code's prompt:

```
Opus 5.5 high │ ██████░░░░ 62% 124k/200k │ $1.37 │ 5h 22% · 7d 8% │ 1h13m │ +120 −34 │ repo ⎇ branch* │ PR #3
```

It shows the model and effort, how full the context window is, the session cost
and your plan usage, plus the branch and its PR. It isn't required for the tmux
integration: drop it from the command if you don't want it. If you already have
a status line of your own, the installer leaves yours alone. Run `./install.sh`
with no arguments to also get the skills and core hooks (see the
[README](../README.md)).

What it does:

- Symlinks the scripts into `~/.claude/bin/` and `claude.tmux` into `~/.claude/`.
  Because these are symlinks, a `git pull` updates them.
- Adds four hooks (and the `statusLine` setting) to `~/.claude/settings.json`. Your existing settings are kept,
  a timestamped backup is written first, and re-running doesn't add duplicates.

## 2. Hook it into tmux

Add one line to `~/.tmux.conf`:

```tmux
source-file -q ~/.claude/claude.tmux
```

Then reload it with `tmux source-file ~/.tmux.conf`, or restart tmux. With `-q`,
the line is silently skipped on machines where you haven't installed it.

**Already using `prefix + C` or `prefix + P`?** Pick other keys. Set them *before*
the `source-file` line:

```tmux
set -g @claude-board-key 'S'
set -g @claude-prs-key   'M-p'
source-file -q ~/.claude/claude.tmux
```

## 3. Restart Claude sessions

Hooks load when Claude Code starts, so sessions that were already open won't
show anything. Quit them and start `claude` again, or open `/hooks` in a
running session to reload.

## 4. Check it works

1. In a tmux window inside a git repo, run `claude` and send any prompt.
2. The window name should change to `⏳ repo:branch`, then `✅ repo:branch` when
   Claude finishes. You should also see a notification.
3. Ask for something that needs permission (e.g. "create a file"). The window
   should change to `❗`.
4. Press `prefix + C`. The session should be on the board.
5. Press `prefix + P`. Your open PRs should be listed.

## Make it look good (optional)

The integration sets tmux window options, and your status bar can read them.
Add this to `~/.tmux.conf` and change the colors to match your theme. If you
already have a `status-right`, add the `#(...)` part to it instead of replacing it.

```tmux
# Colors for the counter
set -g @claude-waiting-style 'fg=#c4746e,bold'
set -g @claude-done-style    'fg=#87a987'

# ❗2 ✅1 counter of sessions waiting / done across all tmux sessions.
# Prints nothing when both are zero.
set -g status-right '#(~/.claude/bin/claude-tmux-counts.sh 2>/dev/null)│ %H:%M '

# Windows where Claude is waiting on you turn red
setw -g window-status-format ' #{?#{==:#{@claude_state},waiting},#[fg=#c4746e]#[bold],}#I:#W '
```

tmux re-runs `#(...)` every `status-interval` seconds (15 by default). Set
`set -g status-interval 5` if you want the counter to update faster.

Window options you can use in your own formats:

| Option | Value |
|---|---|
| `@claude_state` | `working`, `done` or `waiting` |
| `@claude_repo` | `repo:branch` |
| `@claude_pr` | the branch's PR URL, once `gh` finds one |

## How it works

```
Claude Code hook ──▶ claude-tmux-status.sh <state>
                        ├─ rename window, set @claude_* options
                        ├─ gh pr view (background) ─▶ @claude_pr
                        └─ desktop notification (done / waiting only)

prefix + C ──▶ claude-sessions.sh   reads @claude_* from every window
prefix + P ──▶ claude-prs.sh        gh search prs --author @me
```

| Hook event | Matcher | State |
|---|---|---|
| `UserPromptSubmit` | – | `working` |
| `PostToolUse` | – | `working` (clears `❗` once you approve a permission prompt) |
| `Stop` | – | `done` |
| `Notification` | `permission_prompt\|elicitation_dialog` | `waiting` |

The 60-second idle notice is left out of the `Notification` matcher on purpose.
Otherwise a finished `✅` session would flip back to `❗` after a minute.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Window name never changes | Restart the Claude session (hooks load at startup). Check `~/.claude/settings.json` has the `claude-tmux-status.sh` hooks. |
| `prefix + C` does nothing | `tmux list-keys -T prefix \| grep claude`. Nothing listed means the `source-file` line didn't load. Check the path and reload. |
| Name changes back by itself | Something else renames the window, e.g. a shell prompt setting the title or a plugin. The script turns off `automatic-rename` for Claude windows only. |
| No PRs on the board / `prefix + P` errors | `gh auth status`. The PR lookup runs on `done`/`waiting`, so it appears after the first turn. |
| No notification | `CLAUDE_NOTIFY=0` turns them off, so check it isn't set. On Linux, check `notify-send` works on its own. On WSL, Windows Focus Assist / Do Not Disturb hides toasts. |
| Installer says `~/.claude/bin is a symlink` | A dotfiles manager (e.g. stow) owns that directory. Unlink it and re-run. |
| Notifications without tmux? | Yes. They work in any terminal. Window renaming and popups need tmux. |

## Uninstall

1. Remove the `source-file` line (and any theming) from `~/.tmux.conf`.
2. Remove the four `claude-tmux-status.sh` hook entries from
   `~/.claude/settings.json`, or restore the `settings.json.bak.*` backup.
3. `rm ~/.claude/claude.tmux ~/.claude/bin/claude-*.sh`
