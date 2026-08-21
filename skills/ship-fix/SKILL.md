---
name: ship-fix
description: Fix one diagnosed issue with a minimal surgical change, verify tests pass, and produce an atomic commit with a written justification. Use after an audit finding is chosen, or whenever asked to fix an issue with clean atomic commits.
---

# Ship One Fix

Input: one diagnosed issue (from `/audit` or given directly). Output: one atomic commit containing the fix + its justification. Never batch multiple issues into one commit.

## 1. Confirm root cause

Read the affected code and its callers. State in one sentence: *the root cause is X; the symptom is Y.* If you can trigger the bug (a curl command, a failing test you write, a query), do it — proof of the bug before the fix makes the justification airtight.

## 2. Minimal fix

- Change ONLY what the root cause requires. No drive-by refactors, no renames, no formatting churn, no "while I'm here."
- Match the existing code style exactly.
- Preserve existing behavior for all legitimate inputs. If the fix must change observable behavior (e.g., password hashing upgrade, stricter validation), design a migration path: accept-old-verify-new, rehash-on-login, feature flag, or a documented breaking-change note. Never silently break existing consumers.
- If a security fix warrants it and time permits, add ONE focused test proving the vulnerability is closed.

## 3. Verify

- Run the full test suite, using the command established at baseline. Every test that passed at baseline must still pass. If a pre-existing test fails because it was asserting the buggy behavior, say so explicitly in the justification rather than silently editing the test.
- Typecheck and build, again with the project's own commands.
- Re-run the reproduction from step 1 and confirm it's fixed.

## 4. Commit + justify

Append to `FINDINGS.md` at repo root:

```markdown
## <n>. <Short title> — <severity>

**Problem:** what is wrong and where (file:line).
**Impact:** how it's exploited/triggered and what breaks at scale.
**Root cause:** why it happens (not the symptom).
**Fix:** what changed and why this approach; note any migration/compat considerations.
**Verification:** tests run, repro confirmed fixed.
```

Then commit atomically — the fix, its test, and the FINDINGS.md entry together:

```
fix(<area>): <what was fixed>

Problem: <one sentence>
Root cause: <one sentence>
Fix: <one sentence, incl. compat note if any>
```

Keep each justification under ~120 words. Clear and brief beats lengthy.

## 5. Loop

Report status: issues fixed, tests green, time spent. Ask which finding is next (or take the next one from the priority list).
