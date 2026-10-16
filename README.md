# claude-trove

Claude Code configuration: skills, hooks, a status line, a tmux integration,
permissions and templates. It's all in one repo, so a new machine is one
`git clone` away from a working setup. Install all of it, or only the modules
you want.

**Here for the tmux integration?** See the [setup guide](docs/tmux.md).

```bash
./install.sh                     # the default modules
./install.sh statusline tmux     # just the pieces you want
./install.sh --all               # everything, opt-in modules included
./install.sh --list              # what's available
./install.sh --dry-run           # show exactly what would change, touch nothing
```

| Module | Default | What you get |
|---|---|---|
| `skills` | yes | `/audit` `/ship-fix` `/prep-pr` `/i-have-adhd` |
| `core` | yes | Format on edit, background tests on stop, branch warning on main, safe permissions |
| `statusline` | yes | Model, context window, cost, plan usage, git branch and PR under the prompt |
| `tmux` | yes | Session board (`prefix+C`), open PRs (`prefix+P`), window state, desktop notifications |
| `pr-nudge` | no | Has Claude open a PR once a change gets big |
| `task` | no | `/task` skill for taskwarrior + bugwarrior |

Needs `jq`. The tmux module also wants `fzf` and `gh`. Works on Linux, macOS and WSL.

Skills are symlinked, so editing this repo takes effect immediately — no reinstall.
Settings are *merged*: your existing keys survive, arrays are unioned, and
re-running never stacks duplicate hooks (a hook is matched by the script it
runs). A timestamped backup is written first. A status line you wrote yourself
is left alone.

## The one thing worth knowing

Three mechanisms, three jobs. Putting a request in the wrong one is why configs
fail to do what you asked:

| Want | Mechanism | Why not the others |
|---|---|---|
| A workflow you invoke | **skill** (`skills/`) | — |
| Something that *always* happens on an event | **hook** (`settings/`) | A skill or CLAUDE.md is a suggestion the model can skip. A hook is executed by the harness. |
| A tool with no good CLI | **MCP** (`mcp/`) | Every MCP server's tool list is loaded into every session. |

## Skills

| Skill | What it does |
|---|---|
| `/audit` | Baseline → map architecture → sweep security/perf/reliability/tooling → prioritized findings table |
| `/ship-fix` | One finding → root cause → minimal fix → tests green → atomic commit + `FINDINGS.md` justification |
| `/prep-pr` | Verify branch → `/code-review` → scan for debug leftovers and secrets → draft PR title and body |

Deliberately short. Every skill's description is loaded into context every
session, so ten sharp skills beat forty vague ones.

**Do not rebuild what ships built-in.** `/code-review`, `/security-review`,
`/simplify`, `/run`, and `/init` already exist and are better than a hand-rolled
version. Write skills for the glue *around* them.

## Hooks

The lint and test hooks dispatch through `hooks/detect-stack.sh`, which walks up to the project
root and works out the real commands. Precedence: **declared scripts
(package.json, Makefile) → tool config files → nothing.** When a project
declares nothing, the hooks no-op — that is correct, not a failure.

| Hook | Event | Behavior |
|---|---|---|
| `lint-file.sh` | `PostToolUse` on `Write\|Edit` | Formats the one file that changed. Never blocks, never fails the tool call. |
| `run-tests.sh` | `Stop` | Runs the project's verification command **in the background** via `asyncRewake`. Your turn ends immediately. Silent on pass; on failure it wakes Claude with the last 40 lines. Skips entirely when the tree is clean. |
| `branch-guard.sh` | `PreToolUse` on `Write\|Edit` | First edit of a tracked file on the default branch: suggests branching first. Advisory, once per session. |
| `pr-nudge.sh` *(opt-in)* | `Stop` | Background check; once a change touches 2+ files or 80+ lines in one file, wakes Claude to open a PR. Opt out per repo with `touch .git/claude-no-pr`, or everywhere with `PR_NUDGE_OFF=1`. |

Supported out of the box: node (pnpm/bun/yarn/npm), python (uv/poetry/pip),
rust, go, and any `Makefile` with a `test`/`check`/`ci` target.

A note on the node case: `bun exec` does not resolve binaries in `node_modules`
— `bunx` does. `detect-stack.sh` picks the right runner per manager.

## Status line

```
Opus 5.5 high │ ██████░░░░ 62% 124k/200k │ $1.37 │ 5h 22% · 7d 8% │ 1h13m │ +120 −34 │ repo ⎇ branch* │ PR #3
```

Model and effort, how full the context window is, what the session would cost
at API prices, your plan's 5-hour and weekly usage (subscription logins only),
how long the session has run, lines changed, repo and branch (`*` = uncommitted
changes), and the PR Claude Code found for the branch. The gauges turn yellow
at 50% and red at 80%. On a Pro/Max plan you aren't billed the dollar figure;
the 5h/7d numbers are the limits that matter.

## tmux

Full walkthrough, theming and troubleshooting: **[docs/tmux.md](docs/tmux.md)**.

Every window running Claude is renamed `⏳ repo:branch` (working), `✅` (done) or
`❗` (waiting on you), and you get a desktop notification when a session
finishes or needs input: a Windows toast on WSL, Notification Center on macOS,
`notify-send` on Linux. Set `CLAUDE_NOTIFY=0` to silence it. Notifications work
outside tmux too.

| Key | Popup |
|---|---|
| `prefix + C` | Session board: every Claude window, waiting first. `Enter` jumps there, `Ctrl-O` opens its PR. |
| `prefix + P` | All your open PRs across repos. `Enter` opens one in the browser. |

Hook it into tmux with one line in `~/.tmux.conf`:

```tmux
source-file -q ~/.claude/claude.tmux
```

To use other keys, set `@claude-board-key` / `@claude-prs-key` before that line.

How the state gets there: the hooks call `claude-tmux-status.sh <state>`, which
stores it as tmux window options that the popups and status bar read
(`@claude_state`, `@claude_repo`, and `@claude_pr`, the branch's PR looked up
with `gh pr view` in the background).

| Hook event | Matcher | State |
|---|---|---|
| `UserPromptSubmit` | – | `working` |
| `PostToolUse` | – | `working` (clears `❗` once you approve a permission prompt) |
| `Stop` | – | `done` |
| `Notification` | `permission_prompt\|elicitation_dialog` | `waiting` (the 60s idle notice is excluded so it doesn't flip `✅` back to `❗`) |

On WSL there's no `xdg-open`, so URLs go through `wslview` or `explorer.exe`,
and the toast uses the WinRT API built into `powershell.exe`. PowerShell takes
about a second to start, so the toast runs in the background and never slows
Claude down.

Optional theming: put `#(~/.claude/bin/claude-tmux-counts.sh)` in
`status-right` for a `❗2 ✅1` counter, and color it with the
`@claude-waiting-style` / `@claude-done-style` options. `tmux/claude.tmux` has
the details.

## Permissions

`settings/core.json` allowlists read-only git/gh/search commands and the
standard test runners, so they stop prompting. Denies force-push, hard reset,
and reads of `.env` / private keys.

## Templates

`templates/CLAUDE.md.node` and `.python` — starting points to drop into a repo
root and fill in. Thirty seconds spent here keeps every later prompt on-rails.

## GitHub

Use the `gh` CLI, not a GitHub MCP server. It is already authenticated and
costs zero context; the MCP server injects a large tool list into every
session for capability you already have. Save MCP for things with no CLI —
see `mcp/.mcp.json.example`.

## Layout

```
skills/<name>/SKILL.md   one skill per directory, symlinked into ~/.claude/skills
hooks/detect-stack.sh    shared stack detection (sourced, not run directly)
hooks/lint-file.sh       PostToolUse: format the edited file
hooks/run-tests.sh       Stop: background verification run
hooks/branch-guard.sh    PreToolUse: warn before editing on the default branch
hooks/pr-nudge.sh        Stop: open a PR once a change is big (opt-in)
statusline/statusline.sh the status line
docs/tmux.md             tmux setup guide
tmux/                    hook + popup scripts (linked into ~/.claude/bin) and claude.tmux
lib/platform.sh          open a URL / send a notification on WSL, macOS or Linux
settings/<module>.json   each module's hooks/permissions, merged by install.sh (__TROVE__ = repo path)
templates/               CLAUDE.md starting points per stack
mcp/.mcp.json.example    MCP servers worth having
install.sh
```
