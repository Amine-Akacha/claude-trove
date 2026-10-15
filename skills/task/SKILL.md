---
name: task
description: Manage the user's taskwarrior tasks and their bugwarrior-synced GitHub issues — triage what to work on, add tasks, complete them, annotate, reschedule, and sync from GitHub. Use whenever the user asks about their tasks, todos, backlog, what to work on, assigned GitHub issues, or says /task.
user-invocable: true
allowed-tools:
  - Bash(task:*)
  - Bash(bugwarrior:*)
  - Bash(gh:*)
  - Read
---

# /task — taskwarrior + GitHub

Front-end for the user's taskwarrior database and the GitHub issues bugwarrior
syncs into it.

## Environment

| Thing | Value |
|---|---|
| Task data | `~/.task` (taskwarrior 3.4.2, SQLite backend) |
| Config | `~/.taskrc`, which `include`s `~/.config/task/bugwarrior-udas.rc` |
| Bugwarrior config | `~/.config/bugwarrior/bugwarrior.toml` |
| Binaries | `task` on PATH; bugwarrior in `~/.local/bin` |
| Both configs are stowed from | the `wsl_setup` dotfiles repo (`dots/bugwarrior/`) |

Two kinds of task live in the database:

- **`+gh`** — synced from GitHub by bugwarrior. Carries `githubrepo`,
  `githubnumber`, `githuburl`, `githubstate` and friends as UDAs.
- **everything else** — typed by hand, owned entirely locally. The user has
  ~270 of these, tagged things like `Hubspot`, `Stax`, `Azure`, `Scott`.

## The one rule that matters

**For `+gh` tasks, GitHub is the source of truth, not taskwarrior.**

`bugwarrior pull` reconciles every `+gh` task against GitHub, and
`bugwarrior/db.py` explicitly reopens any task it finds completed whose issue is
still open:

```python
if task['status'] == 'completed':
    task['status'] = 'pending'   # ← your `task done` gets undone
    task['end'] = None
```

So running `task done` on a `+gh` task **does not stick** — the next sync
resurrects it. To actually finish one, close it upstream first (see below).

The same applies to edits: a pull overwrites `description`, `project` and `tags`
on `+gh` tasks from GitHub. Only `priority` is protected (it's in
`static_fields`). If the user wants a durable local note on a synced task, use
an **annotation** — those are merged, not clobbered.

## Reading tasks

Always read as JSON and filter in your head rather than parsing the table:

```bash
task +PENDING export            # everything open
task +gh +PENDING export        # just synced GitHub issues
task +PENDING -gh export        # just their hand-written tasks
task project:Precision-Tax-Relief.ptr-web-app export
task +OVERDUE export
```

`task <filter> list` / `task next` are fine when you want to *show* the user
something, since the formatted table is what they're used to seeing. Note IDs
shift as tasks come and go — **use `uuid` for any multi-step operation**, and
only use short IDs in a single immediate command.

When the user refers to a task in prose ("the textline one", "the stax login
thing"), export the pending set and match on description yourself. If two
plausibly match, ask which — don't guess and mutate the wrong one.

## Triage — "what should I work on?"

The default `/task` with no clear instruction. Don't just dump 280 rows.

1. `task +PENDING export` and look at `urgency`, `due`, `+OVERDUE`, `+ACTIVE`.
2. Lead with anything already `start`ed, then overdue, then top urgency.
3. Show ~5–10 grouped by project or theme, with a one-line reason each.
4. Mention the `+gh` vs local split if it's informative.

Offer to sync first if the last pull looks stale.

## Syncing from GitHub

```bash
bugwarrior pull
```

Pulls every open issue and PR **assigned to the user** across personal, member
and org repos (`GET /issues`), then adds / updates / closes tasks to match. It
prints `Adding N / Updating N / Closing N` — relay those counts.

- Auth comes from the `gh` CLI at pull time (`token = "@oracle:eval:gh auth token"`).
  If it fails with 401, `gh auth status` is the first thing to check.
- It is safe to run repeatedly and never touches non-`+gh` tasks.
- A pull takes a couple of seconds; just run it when the user asks to sync, or
  when the GitHub picture needs to be current before you answer.

## Completing a task

**Local task** — straightforward:

```bash
task <id> done
```

**`+gh` task** — close it on GitHub, then sync, or it comes back:

```bash
# 1. read the coordinates off the task
task <id> export | jq -r '.[0] | .githubrepo, .githubnumber'
# 2. close upstream
gh issue close <githubnumber> --repo <githubrepo> --comment "<optional>"
# 3. reconcile — bugwarrior reports "Closing 1 tasks"
bugwarrior pull
```

Closing an issue is a public, outward-facing action on a repo that may be shared
with the user's team. **Confirm before closing anything under an org they don't
solely own** (e.g. `Precision-Tax-Relief/*`), and quote the issue title back to
them. For a PR it's `gh pr close`. If the user only wants it off their plate
without closing the issue, the honest options are to unassign themselves
(`gh issue edit <n> --repo <r> --remove-assignee @me`) or to accept it will
reappear — say so rather than running a `task done` you know will be undone.

## Adding a task

Local tasks only — never create a `+gh` task by hand, it'll collide with the
next sync. Let the user's own tag vocabulary guide you (`task _tags`).

```bash
task add "description" project:Foo +tag due:friday priority:H
```

Priority is a UDA here with values `H`, `M`, `L` or empty — no other values.
Dates accept taskwarrior's synonyms: `today`, `tomorrow`, `eow`, `friday`,
`2026-08-20`.

To turn a GitHub issue into a local task *without* syncing (e.g. one not
assigned to them), pull the title with `gh issue view` and `task add` it with
the URL as an annotation.

## Other operations

```bash
task <id> start / stop                  # time tracking, sets +ACTIVE
task <id> annotate "note"               # durable even on +gh tasks
task <id> modify due:tomorrow priority:H project:Foo
task <id> modify +tag -oldtag
task <id> delete                        # for local tasks; on +gh it returns on sync
task <id> info                          # full detail incl. UDAs and history
task summary / task burndown.daily      # reports
```

For any command that would touch more than one task, taskwarrior prompts. Add
`rc.confirmation=off` **only** when the user has clearly authorized the batch —
otherwise let it prompt, or run the tasks one at a time so a mistake is small.

## Safety

- `task delete` and bulk `modify` are hard to undo. Confirm the exact matched
  set with the user before running one that spans several tasks.
- Backups live in `~/.task-backups/`. Before any risky bulk operation:
  `task export > ~/.task-backups/pre-<what>-$(date +%Y%m%d-%H%M%S).json`
- Never hand-edit `github*` UDAs — bugwarrior owns them and uses
  `githubrepo` + `githubnumber` as the identity key for matching.

## Adding Jira later

The user originally wanted Jira too and the `jira` python extra is already
installed. `~/.config/bugwarrior/bugwarrior.toml` has a commented `[jira]`
block: uncomment it, add `"jira"` to `targets`, drop an API token in
`~/.config/bugwarrior/jira-token` (chmod 600), then regenerate the UDAs:

```bash
bugwarrior uda > ~/wsl-setup/wsl_setup/dots/bugwarrior/.config/task/bugwarrior-udas.rc
```
