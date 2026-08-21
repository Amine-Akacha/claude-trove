#!/usr/bin/env bash
# Sourced by the other hooks. Walks up from $PWD to a project root and works
# out what this project actually uses to lint and verify itself.
#
# Precedence, strongest signal first:
#   1. scripts the project declares (package.json scripts, Makefile targets)
#   2. tool config files present at the root
#   3. nothing -- the hooks then no-op, which is the correct behavior
#
# Exports: PROJ_ROOT PROJ_KIND PM LINT_CMD TEST_CMD TEST_LABEL
# LINT_CMD is a template containing {} for the file path; it runs per-file.
# TEST_CMD is the whole-project verification command. Either may be empty.

find_root() {
  local d="$PWD"
  while [ "$d" != "/" ]; do
    for m in package.json pyproject.toml Cargo.toml go.mod requirements.txt Makefile .git; do
      [ -e "$d/$m" ] && { echo "$d"; return; }
    done
    d="$(dirname "$d")"
  done
  echo "$PWD"
}

PROJ_ROOT="$(find_root)"
PROJ_KIND=""; PM=""; LINT_CMD=""; TEST_CMD=""; TEST_LABEL=""

has()  { command -v "$1" >/dev/null 2>&1; }
kind() { PROJ_KIND="${PROJ_KIND:+$PROJ_KIND+}$1"; }
# any_file <dir> <pattern>... -- true if any pattern matches, no glob leakage
any_file() {
  local d="$1"; shift
  local p f
  for p in "$@"; do
    for f in "$d"/$p; do [ -e "$f" ] && return 0; done
  done
  return 1
}

# Does package.json declare this script?
npm_script() { jq -e --arg s "$1" '.scripts[$s] // empty' "$PROJ_ROOT/package.json" >/dev/null 2>&1; }
# Does the Makefile declare this target?
make_target() { [ -f "$PROJ_ROOT/Makefile" ] && grep -qE "^$1:" "$PROJ_ROOT/Makefile"; }

# --- node -----------------------------------------------------------------
if [ -f "$PROJ_ROOT/package.json" ]; then
  kind node
  if   [ -f "$PROJ_ROOT/pnpm-lock.yaml" ] && has pnpm; then PM="pnpm"
  elif [ -f "$PROJ_ROOT/bun.lockb" ] || [ -f "$PROJ_ROOT/bun.lock" ] && has bun; then PM="bun"
  elif [ -f "$PROJ_ROOT/yarn.lock" ] && has yarn; then PM="yarn"
  else PM="npm"
  fi
  [ "$PM" = npm ] && RUN="npm run" || RUN="$PM run"
  # Running a binary out of node_modules differs per manager: `bun exec` does
  # NOT resolve them, `bunx` does.
  case "$PM" in
    bun)  EXEC="bunx" ;;
    pnpm) EXEC="pnpm exec" ;;
    yarn) EXEC="yarn exec" ;;
    *)    EXEC="npx --no-install" ;;
  esac

  # Verification: real tests beat a typecheck, a typecheck beats nothing.
  for s in test typecheck ci check; do
    npm_script "$s" && { TEST_CMD="$RUN $s"; TEST_LABEL="$s"; break; }
  done

  # Per-file formatting. A declared script formats the WHOLE tree, which is
  # too broad for an on-edit hook -- so use it only to learn which formatter
  # this project uses, then invoke that formatter on the one file.
  if npm_script format && jq -re '.scripts.format' "$PROJ_ROOT/package.json" | grep -q biome; then
    LINT_CMD="$EXEC biome check --write {}"
  elif npm_script format && jq -re '.scripts.format' "$PROJ_ROOT/package.json" | grep -q prettier; then
    LINT_CMD="$EXEC prettier --write --ignore-unknown {}"
  elif [ -f "$PROJ_ROOT/biome.json" ] || [ -f "$PROJ_ROOT/biome.jsonc" ]; then
    LINT_CMD="$EXEC biome check --write {}"
  elif any_file "$PROJ_ROOT" '.prettierrc*' 'prettier.config.*' \
    || jq -e '.prettier' "$PROJ_ROOT/package.json" >/dev/null 2>&1; then
    LINT_CMD="$EXEC prettier --write --ignore-unknown {}"
  fi
fi

# --- python ---------------------------------------------------------------
if [ -f "$PROJ_ROOT/pyproject.toml" ] || [ -f "$PROJ_ROOT/requirements.txt" ]; then
  kind python
  if   has uv && [ -f "$PROJ_ROOT/uv.lock" ]; then PY="uv run "
  elif has poetry && grep -q '^\[tool\.poetry\]' "$PROJ_ROOT/pyproject.toml" 2>/dev/null; then PY="poetry run "
  else PY=""
  fi
  # Only reach for ruff if the project opted into it -- never auto-install a
  # formatter the project never asked for.
  if grep -q 'ruff' "$PROJ_ROOT/pyproject.toml" 2>/dev/null || [ -f "$PROJ_ROOT/ruff.toml" ]; then
    if has ruff || [ -n "$PY" ]; then
      LINT_CMD="${LINT_CMD:-${PY}ruff format {} && ${PY}ruff check --fix {}}"
    fi
  elif grep -q 'black' "$PROJ_ROOT/pyproject.toml" 2>/dev/null && { has black || [ -n "$PY" ]; }; then
    LINT_CMD="${LINT_CMD:-${PY}black -q {}}"
  fi
  if [ -z "$TEST_CMD" ]; then
    if [ -d "$PROJ_ROOT/tests" ] || [ -d "$PROJ_ROOT/test" ] \
       || grep -q 'pytest' "$PROJ_ROOT/pyproject.toml" "$PROJ_ROOT/requirements.txt" 2>/dev/null; then
      TEST_CMD="${PY}pytest -q"; TEST_LABEL="pytest"
    fi
  fi
fi

# --- rust / go ------------------------------------------------------------
if [ -f "$PROJ_ROOT/Cargo.toml" ]; then
  kind rust
  LINT_CMD="${LINT_CMD:-rustfmt {}}"
  [ -z "$TEST_CMD" ] && { TEST_CMD="cargo test"; TEST_LABEL="cargo test"; }
fi
if [ -f "$PROJ_ROOT/go.mod" ]; then
  kind go
  LINT_CMD="${LINT_CMD:-gofmt -w {}}"
  [ -z "$TEST_CMD" ] && { TEST_CMD="go test ./..."; TEST_LABEL="go test"; }
fi

# --- Makefile: last resort, but it beats guessing -------------------------
if [ -z "$TEST_CMD" ]; then
  for t in test check ci; do
    make_target "$t" && { TEST_CMD="make $t"; TEST_LABEL="make $t"; kind make; break; }
  done
fi

export PROJ_ROOT PROJ_KIND PM EXEC LINT_CMD TEST_CMD TEST_LABEL
