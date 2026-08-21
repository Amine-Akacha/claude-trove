---
name: audit
description: Systematically audit an unfamiliar codebase for security, performance, reliability, and tooling issues. Use when asked to audit, review, or find issues in a codebase.
---

# Codebase Audit

Audit this codebase end-to-end. Work in phases; do not skip Phase 0 or 1. Time-box: this whole skill should finish within ~20 minutes so most of the session is left for fixes.

## Phase 0 — Baseline (5 min max)

Establish that the project works BEFORE touching anything. All findings and fixes are measured against this baseline.

1. `git log --oneline -15` and `git status` — understand starting state
2. **Identify the stack before running anything.** Read whichever manifest exists and learn the project's own commands from it — never assume:

   | Marker | Manifest to read | Install / test / build |
   |---|---|---|
   | `package.json` | + lockfile (`pnpm-lock.yaml`, `bun.lock*`, `yarn.lock`) and `turbo.json`/`nx.json` | the matching manager's `install` / `run test` / `run build` |
   | `pyproject.toml` | + `uv.lock` or `[tool.poetry]` | `uv sync` / `poetry install`, then `pytest` |
   | `requirements.txt` | — | `pip install -r`, then `pytest` |
   | `Cargo.toml` | — | `cargo build` / `cargo test` |
   | `go.mod` | — | `go build ./...` / `go test ./...` |
   | `Makefile` | its targets | whatever `test` / `check` / `ci` runs |

   A declared script always beats a guess. If several markers are present, it is a polyglot repo — baseline each part.

3. Install dependencies with the command from step 2.
4. Run the test suite. **Record which tests pass — this is the compatibility contract.** If the project has no tests, that is itself a finding; note it and use typecheck/build as the contract instead.
5. Build. If it is a service, start it in the background and confirm it responds.

If install/build/test is itself broken, that IS a developer-tooling finding in its own right — diagnose it first, it blocks everything else.

## Phase 1 — Map the system (5 min max)

Launch parallel Explore agents (or do it directly if the repo is small):
- Package graph: what packages exist, who depends on whom, where are entry points
- Backend: framework, routes/endpoints, middleware chain, DB access layer, auth flow
- Frontend: framework, data fetching pattern, state management
- Config: tsconfig strictness, ESLint, CI workflows, env var handling

Write a 10-line architecture summary before proceeding. Findings must reference this map.

## Phase 2 — Sweep by category

Grep-driven, hypothesis-first. For each hit, read surrounding code to confirm root cause — never report a symptom without the cause.

### Security (highest value — check first)
- **Injection**: string-concatenated SQL (`` `SELECT ... ${ ``, `" + req.`), `child_process.exec` with user input, `eval`/`new Function`
- **Auth**: routes missing auth middleware (diff protected vs unprotected route lists), JWT with `none` alg, hardcoded/weak secrets, tokens in localStorage, missing ownership checks (IDOR — `findById(req.params.id)` without user scoping)
- **Passwords**: `md5`/`sha1`/plain comparison; should be bcrypt/argon2 with per-user salt
- **XSS**: `dangerouslySetInnerHTML`, `innerHTML =`, unescaped template output
- **Secrets**: grep for `api_key`, `secret`, `password` literals committed to the repo; `.env` in git
- **CORS/headers**: `origin: '*'` with credentials, missing helmet/CSP, `httpOnly`/`secure`/`sameSite` absent on session cookies
- **Path traversal**: `path.join(base, req.params.file)` / `res.sendFile` with user input
- **Mass assignment**: spreading `req.body` straight into DB create/update
- **Validation**: endpoints trusting `req.body`/`req.query` types with no zod/joi/manual validation

### Performance
- **N+1 queries**: DB call inside a loop or a `.map` over query results
- **Missing pagination**: `findAll()`/`SELECT *` returned to the client unbounded
- **Blocking the event loop**: `readFileSync`/crypto/heavy sync work in request handlers
- **No caching / cache stampede**: repeated identical expensive calls; unbounded in-memory caches (memory leak)
- **Frontend**: fetch-in-render loops, missing `key`s, effect dependency bugs causing refetch storms, huge unpaginated list renders
- **Missing DB indexes** on columns used in WHERE/JOIN (check schema/migrations)

### Reliability
- **Unhandled rejections**: async route handlers with no try/catch and no error middleware wrapper
- **Swallowed errors**: empty `catch {}`, `catch (e) { console.log(e) }` then continuing
- **No timeouts**: `fetch`/axios/DB calls without timeout or retry semantics
- **Race conditions**: read-modify-write without transaction/lock (balance updates, counters, upserts)
- **Missing transactions**: multi-step writes that must be atomic
- **Process crash**: throwing inside event emitters / setInterval; missing graceful shutdown

### Developer tooling
- `tsconfig`: `strict: false`, `noImplicitAny: false`, `skipLibCheck` masking real errors
- Lint/format not enforced or misconfigured; scripts that silently no-op (`|| true`, `--passWithNoTests`)
- CI missing steps (no typecheck, no test run), wrong node version pinning
- Tests that assert nothing, are skipped (`it.skip`, `xdescribe`), or mock the thing they claim to test
- Lockfile drift, phantom dependencies (imports not declared in that package's package.json)

## Phase 3 — Prioritized findings

Output a table, sorted by (severity × confidence ÷ fix effort):

| # | Category | File:line | Root cause (one sentence) | Severity | Fix effort |

Then recommend the fix order: **confident high-severity first**. In a time-boxed session, 2–3 excellent fixes beat 6 shallow ones. Note remaining unfixed findings in a `FINDINGS.md` at repo root — a documented diagnosis is worth keeping even when the fix doesn't ship.

After the table, hand off to `/ship-fix` for each finding, one at a time.
