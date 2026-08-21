# claude-trove

Personal Claude Code configuration: skills, hooks, permissions, and templates,
in one repo so a new machine is one `git clone` away from a working setup.

```bash
./install.sh              # symlink skills + merge hooks/permissions into ~/.claude
./install.sh --dry-run    # show exactly what would change, touch nothing
./install.sh --skills     # skills only, leave settings.json alone
```

Skills are symlinked, so editing this repo takes effect immediately — no reinstall.
Settings are *merged*: your existing keys survive, arrays are unioned, and
re-running never stacks duplicate hooks. A timestamped backup is written first.

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

Both dispatch through `hooks/detect-stack.sh`, which walks up to the project
root and works out the real commands. Precedence: **declared scripts
(package.json, Makefile) → tool config files → nothing.** When a project
declares nothing, the hooks no-op — that is correct, not a failure.

| Hook | Event | Behavior |
|---|---|---|
| `lint-file.sh` | `PostToolUse` on `Write\|Edit` | Formats the one file that changed. Never blocks, never fails the tool call. |
| `run-tests.sh` | `Stop` | Runs the project's verification command **in the background** via `asyncRewake`. Your turn ends immediately. Silent on pass; on failure it wakes Claude with the last 40 lines. Skips entirely when the tree is clean. |

Supported out of the box: node (pnpm/bun/yarn/npm), python (uv/poetry/pip),
rust, go, and any `Makefile` with a `test`/`check`/`ci` target.

A note on the node case: `bun exec` does not resolve binaries in `node_modules`
— `bunx` does. `detect-stack.sh` picks the right runner per manager.

## Permissions

`settings/settings.json` allowlists read-only git/gh/search commands and the
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
settings/settings.json   hooks + permissions, merged by install.sh (__TROVE__ = repo path)
templates/               CLAUDE.md starting points per stack
mcp/.mcp.json.example    MCP servers worth having
install.sh
```
