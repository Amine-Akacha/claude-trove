---
name: prep-pr
description: Get a branch ready to open as a pull request - verify it builds and passes, review the diff for defects, then draft the PR title and body. Use before opening a PR, or when asked to "prep", "check my branch", or "write the PR description".
---

# Prep a PR

Take the current branch from "I think it's done" to "ready for a reviewer". Do not open the PR — produce everything needed and hand it over.

## 1. Scope the change

```bash
git status
git log --oneline "$(git merge-base HEAD origin/HEAD)..HEAD"
git diff "$(git merge-base HEAD origin/HEAD)...HEAD" --stat
```

State in one line what this branch does. If the diff spans several unrelated concerns, say so now — that is a "split this PR" finding, and it is cheaper to raise before review than after.

## 2. Verify it actually works

Run what the project declares, in this order. Skip a step only if the project has no such command, and say which you skipped.

- Install (only if lockfiles changed)
- Typecheck / build
- Lint
- Full test suite

**Report real output.** If something fails, that is the finding — fix it or surface it. Never write "tests pass" without having run them.

## 3. Review your own diff

Invoke `/code-review` on the branch. It is better at this than an ad-hoc read-through, and it is already installed.

Then check the things a diff review misses:
- Debug leftovers: stray logging, commented-out code, `TODO`/`FIXME` you added, focused tests (`.only`, `test.skip`)
- Secrets or credentials in the diff, including in fixtures and `.env.example`
- Files that should not be committed: build output, local config, editor state
- Migrations, config, or env vars that need a deploy-time step

## 4. Draft the PR

Write the title as an imperative summary under ~70 chars. Then the body:

```markdown
## What
One paragraph: the change and the reason for it.

## Why
The problem being solved. Link the issue if there is one.

## How
Only the non-obvious decisions — a reviewer can read the diff for the rest.
Call out anything you chose against, and why.

## Verification
The commands you ran and their results. Be specific: "142 passed" beats "tests pass".

## Risk
Blast radius, rollback plan, anything needing a deploy step.
Write "Low — additive only" when that is true.
```

## 5. Hand off

Print the title and body, then the exact command to open it:

```bash
gh pr create --title "..." --body-file <path>
```

Do not run it. Opening the PR is the user's call.

Use `gh`, not a GitHub MCP server — it is already authenticated and costs no context.
