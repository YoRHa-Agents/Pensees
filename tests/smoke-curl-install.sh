#!/usr/bin/env bash
# tests/smoke-curl-install.sh — end-to-end smoke for get.sh.
#
# Pattern mirrors tests/smoke-install.sh: mktemp a fake $HOME, build a fake
# release tarball, serve it via `python3 -m http.server` on a free port,
# point get.sh at the mock via env vars, and assert filesystem state.
#
# Implements T1..T8 from .local/memory/specs/pensees/v0.3.0-design.md §9.1.3:
#   T1  happy path, pinned tag
#   T2  idempotent re-run
#   T3  upgrade path
#   T4  unsupported platform (CYGWIN faked via PATH shim)
#   T5  missing required tool (tar shadowed out of PATH)
#   T6  tarball 404 / empty
#   T7  --target=cursor passthrough
#   T8  install.sh failure passes through (exit 42)
#
# Total runtime budget: ≤ 30 seconds.  Cleans up the http.server PID and all
# temp dirs in a single EXIT trap.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GET_SH="${REPO_ROOT}/get.sh"

fail_count=0
pass_count=0

pass() { printf '    ok   %s\n' "$1"; pass_count=$((pass_count + 1)); }
fail() { printf '    FAIL %s\n' "$1"; fail_count=$((fail_count + 1)); }

# --- Pre-flight -------------------------------------------------------------

if [[ ! -f "$GET_SH" ]]; then
  echo "[smoke-curl-install] FAIL get.sh missing at $GET_SH"
  exit 1
fi
if [[ ! -x "$GET_SH" ]]; then
  echo "[smoke-curl-install] FAIL get.sh not executable: $GET_SH"
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "[smoke-curl-install] FAIL python3 not on PATH (needed for http.server)"
  exit 1
fi
if [[ ! -d "$REPO_ROOT/skill" ]]; then
  echo "[smoke-curl-install] FAIL repo skill/ dir missing at $REPO_ROOT/skill"
  exit 1
fi

# --- Setup temp dirs --------------------------------------------------------

FAKE_HOME="$(mktemp -d -t pensees-curl-home-XXXX)"
STAGE_DIR="$(mktemp -d -t pensees-curl-stage-XXXX)"
SERVE_DIR="$(mktemp -d -t pensees-curl-serve-XXXX)"
SERVER_PID=""

cleanup() {
  if [[ -n "$SERVER_PID" ]]; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  rm -rf "$FAKE_HOME" "$STAGE_DIR" "$SERVE_DIR" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo "[smoke-curl-install] fake HOME = $FAKE_HOME"
echo "[smoke-curl-install] stage dir = $STAGE_DIR"
echo "[smoke-curl-install] serve dir = $SERVE_DIR"

# --- Build fake release tarballs --------------------------------------------

# T1/T2/T7: v0.3.0-test — happy-path tarball (mirrors the real repo).
mkdir -p "$STAGE_DIR/Pensees-v0.3.0-test"
cp -R "$REPO_ROOT/skill"     "$STAGE_DIR/Pensees-v0.3.0-test/"
cp    "$REPO_ROOT/install.sh" "$STAGE_DIR/Pensees-v0.3.0-test/"
cp    "$REPO_ROOT/README.md"  "$STAGE_DIR/Pensees-v0.3.0-test/"
cp    "$REPO_ROOT/LICENSE"    "$STAGE_DIR/Pensees-v0.3.0-test/"
mkdir -p "$SERVE_DIR/refs/tags"
tar -czf "$SERVE_DIR/refs/tags/v0.3.0-test.tar.gz" -C "$STAGE_DIR" Pensees-v0.3.0-test

# T3: v0.3.0-test-b — a second tag, used for the upgrade test.
mkdir -p "$STAGE_DIR/Pensees-v0.3.0-test-b"
cp -R "$REPO_ROOT/skill"     "$STAGE_DIR/Pensees-v0.3.0-test-b/"
cp    "$REPO_ROOT/install.sh" "$STAGE_DIR/Pensees-v0.3.0-test-b/"
cp    "$REPO_ROOT/README.md"  "$STAGE_DIR/Pensees-v0.3.0-test-b/"
cp    "$REPO_ROOT/LICENSE"    "$STAGE_DIR/Pensees-v0.3.0-test-b/"
tar -czf "$SERVE_DIR/refs/tags/v0.3.0-test-b.tar.gz" -C "$STAGE_DIR" Pensees-v0.3.0-test-b

# T8: v0.3.0-test-bad — tarball with an install.sh that exits 42.
mkdir -p "$STAGE_DIR/Pensees-v0.3.0-test-bad"
cp -R "$REPO_ROOT/skill"   "$STAGE_DIR/Pensees-v0.3.0-test-bad/"
cp    "$REPO_ROOT/README.md" "$STAGE_DIR/Pensees-v0.3.0-test-bad/"
cp    "$REPO_ROOT/LICENSE"   "$STAGE_DIR/Pensees-v0.3.0-test-bad/"
cat > "$STAGE_DIR/Pensees-v0.3.0-test-bad/install.sh" <<'BAD'
#!/usr/bin/env bash
echo "this install.sh is intentionally broken (smoke T8)" >&2
exit 42
BAD
chmod +x "$STAGE_DIR/Pensees-v0.3.0-test-bad/install.sh"
tar -czf "$SERVE_DIR/refs/tags/v0.3.0-test-bad.tar.gz" -C "$STAGE_DIR" Pensees-v0.3.0-test-bad

# --- Pick a free port + start http.server -----------------------------------

PORT=$(python3 -c "import socket; s=socket.socket(); s.bind(('127.0.0.1',0)); print(s.getsockname()[1]); s.close()")
echo "[smoke-curl-install] http port = $PORT"

python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$SERVE_DIR" >/dev/null 2>&1 &
SERVER_PID=$!

# Wait up to ~3s for the server to come up.
server_ready=0
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  if curl -fsS "http://127.0.0.1:$PORT/refs/tags/v0.3.0-test.tar.gz" -o /dev/null 2>/dev/null; then
    server_ready=1
    break
  fi
  sleep 0.2
done
if [[ "$server_ready" != "1" ]]; then
  echo "[smoke-curl-install] FAIL server did not start on 127.0.0.1:$PORT"
  exit 1
fi
pass "T0 mock http.server up at 127.0.0.1:$PORT"

# --- Helper to call get.sh against the mock --------------------------------

# usage: run_get <PENSEES_HOME> <fake-home> <version> [args...]
run_get() {
  local pen_home="$1"; shift
  local fake_home="$1"; shift
  local version="$1"; shift
  PENSEES_HOME="$pen_home" \
  PENSEES_VERSION="$version" \
  PENSEES_DOWNLOAD_URL_BASE="http://127.0.0.1:$PORT" \
  PENSEES_API_URL_BASE="http://127.0.0.1:$PORT" \
  HOME="$fake_home" \
  sh "$GET_SH" "$@"
}

# ============================================================================
# T1: happy path, pinned tag
# ============================================================================
echo "[smoke-curl-install] T1 happy path (pinned tag)"
T1_HOME="$FAKE_HOME/inst"
T1_FAKE_HOME="$FAKE_HOME"
T1_RC=0
T1_OUT=$(run_get "$T1_HOME" "$T1_FAKE_HOME" "v0.3.0-test" 2>&1) || T1_RC=$?
if [[ "$T1_RC" == "0" ]]; then
  pass "T1 get.sh exit 0"
else
  fail "T1 get.sh exited $T1_RC"
  printf '%s\n' "$T1_OUT" | sed 's/^/        /'
fi
if [[ -L "$T1_HOME/current" ]]; then
  target=$(readlink "$T1_HOME/current")
  if [[ "$target" == "Pensees-v0.3.0-test" ]]; then
    pass "T1 current symlink -> Pensees-v0.3.0-test"
  else
    fail "T1 current points at '$target' (expected Pensees-v0.3.0-test)"
  fi
else
  fail "T1 current symlink missing at $T1_HOME/current"
fi
if [[ -f "$T1_HOME/Pensees-v0.3.0-test/skill/SKILL.md" ]]; then
  pass "T1 skill/SKILL.md present in installed tree"
else
  fail "T1 skill/SKILL.md missing in installed tree"
fi
if [[ -L "$T1_FAKE_HOME/.cursor/skills-cursor/pensees" ]]; then
  pass "T1 install.sh ran: cursor symlink present"
else
  fail "T1 install.sh did not run: cursor symlink missing"
fi

# ============================================================================
# T2: idempotency — second run should report [skip] and create no .bak.*
# ============================================================================
echo "[smoke-curl-install] T2 idempotency"
T2_RC=0
T2_OUT=$(run_get "$T1_HOME" "$T1_FAKE_HOME" "v0.3.0-test" 2>&1) || T2_RC=$?
if [[ "$T2_RC" == "0" ]]; then
  pass "T2 second run exit 0"
else
  fail "T2 second run exited $T2_RC"
fi
if grep -q '\[skip\] already at v0.3.0-test' <<<"$T2_OUT"; then
  pass "T2 emitted [skip] already at v0.3.0-test"
else
  fail "T2 did not emit [skip] line"
  printf '%s\n' "$T2_OUT" | sed 's/^/        /'
fi
bak_count=$(find "$T1_HOME" -maxdepth 1 -type d -name '.bak.*' 2>/dev/null | wc -l | tr -d ' \t\n')
if [[ "$bak_count" == "0" ]]; then
  pass "T2 no .bak.* created on idempotent re-run"
else
  fail "T2 unexpected .bak.* dir(s) on idempotent re-run (count=$bak_count)"
fi

# ============================================================================
# T3: upgrade path — switch to v0.3.0-test-b, expect exactly one .bak.<ts>
# ============================================================================
echo "[smoke-curl-install] T3 upgrade path"
T3_RC=0
T3_OUT=$(run_get "$T1_HOME" "$T1_FAKE_HOME" "v0.3.0-test-b" 2>&1) || T3_RC=$?
if [[ "$T3_RC" == "0" ]]; then
  pass "T3 upgrade exit 0"
else
  fail "T3 upgrade exited $T3_RC"
  printf '%s\n' "$T3_OUT" | sed 's/^/        /'
fi
if [[ -L "$T1_HOME/current" ]]; then
  target=$(readlink "$T1_HOME/current")
  if [[ "$target" == "Pensees-v0.3.0-test-b" ]]; then
    pass "T3 current updated to Pensees-v0.3.0-test-b"
  else
    fail "T3 current points at '$target' (expected Pensees-v0.3.0-test-b)"
  fi
else
  fail "T3 current symlink missing after upgrade"
fi
bak_count=$(find "$T1_HOME" -maxdepth 1 -type d -name '.bak.*' 2>/dev/null | wc -l | tr -d ' \t\n')
if [[ "$bak_count" == "1" ]]; then
  pass "T3 exactly one .bak.<ts>/ dir created"
else
  fail "T3 expected 1 .bak.<ts>/, got $bak_count"
fi
bak_dir=$(find "$T1_HOME" -maxdepth 1 -type d -name '.bak.*' 2>/dev/null | head -n 1)
if [[ -n "$bak_dir" && -d "$bak_dir/Pensees-v0.3.0-test" ]]; then
  pass "T3 backup contains the previous Pensees-v0.3.0-test tree"
else
  fail "T3 backup missing previous tree (bak_dir=$bak_dir)"
fi

# ============================================================================
# T4: unsupported platform — fake `uname` via PATH shim
# ============================================================================
echo "[smoke-curl-install] T4 unsupported platform"
SHIM_DIR="$STAGE_DIR/shim-cygwin"
mkdir -p "$SHIM_DIR"
cat > "$SHIM_DIR/uname" <<'SHIM'
#!/bin/sh
echo "CYGWIN_NT-10.0"
SHIM
chmod +x "$SHIM_DIR/uname"

T4_HOME="$FAKE_HOME/inst-t4"
T4_FAKE_HOME="$STAGE_DIR/fake-home-t4"
mkdir -p "$T4_FAKE_HOME"
set +e
T4_OUT=$(PATH="$SHIM_DIR:$PATH" \
         PENSEES_HOME="$T4_HOME" \
         PENSEES_VERSION="v0.3.0-test" \
         PENSEES_DOWNLOAD_URL_BASE="http://127.0.0.1:$PORT" \
         PENSEES_API_URL_BASE="http://127.0.0.1:$PORT" \
         HOME="$T4_FAKE_HOME" \
         sh "$GET_SH" 2>&1)
T4_RC=$?
set -e
if [[ "$T4_RC" == "3" ]]; then
  pass "T4 exit code 3 (unsupported platform)"
else
  fail "T4 expected exit 3, got $T4_RC"
fi
if grep -q "unsupported platform: CYGWIN_NT-10.0" <<<"$T4_OUT"; then
  pass "T4 error names CYGWIN_NT-10.0"
else
  fail "T4 error did not name CYGWIN_NT-10.0"
  printf '%s\n' "$T4_OUT" | sed 's/^/        /'
fi
if grep -q "WSL" <<<"$T4_OUT"; then
  pass "T4 message points to WSL"
else
  fail "T4 message did not mention WSL"
fi

# ============================================================================
# T5: missing required tool — shadow PATH without `tar`
# ============================================================================
echo "[smoke-curl-install] T5 missing tool (tar absent from PATH)"
NOPTAR_DIR="$STAGE_DIR/noptar"
mkdir -p "$NOPTAR_DIR"
# Symlink common tools EXCEPT tar.  This way get.sh's PATH lookup of `tar`
# fails, but everything else (curl, mkdir, mv, rm, uname, sh internals) works.
for tool in sh dash bash curl wget mkdir mv rm uname grep sed awk ln cat \
            printf echo dirname basename mktemp chmod cp ls test wc head \
            tail tr date find readlink xargs sleep kill; do
  t_path=$(command -v "$tool" 2>/dev/null || true)
  if [[ -n "$t_path" && -x "$t_path" ]]; then
    ln -sf "$t_path" "$NOPTAR_DIR/$tool"
  fi
done
T5_HOME="$FAKE_HOME/inst-t5"
T5_FAKE_HOME="$STAGE_DIR/fake-home-t5"
mkdir -p "$T5_FAKE_HOME"
set +e
T5_OUT=$(PATH="$NOPTAR_DIR" \
         PENSEES_HOME="$T5_HOME" \
         PENSEES_VERSION="v0.3.0-test" \
         PENSEES_DOWNLOAD_URL_BASE="http://127.0.0.1:$PORT" \
         PENSEES_API_URL_BASE="http://127.0.0.1:$PORT" \
         HOME="$T5_FAKE_HOME" \
         sh "$GET_SH" 2>&1)
T5_RC=$?
set -e
if [[ "$T5_RC" == "4" ]]; then
  pass "T5 exit code 4 (missing tool)"
else
  fail "T5 expected exit 4, got $T5_RC"
fi
if grep -q "missing required tool: tar" <<<"$T5_OUT"; then
  pass "T5 error names tar"
else
  fail "T5 error did not name tar"
  printf '%s\n' "$T5_OUT" | sed 's/^/        /'
fi

# ============================================================================
# T6: tarball 404 / empty — point at a tag that does not exist on the mock
# ============================================================================
echo "[smoke-curl-install] T6 404 / empty tarball"
T6_HOME="$FAKE_HOME/inst-t6"
T6_FAKE_HOME="$STAGE_DIR/fake-home-t6"
mkdir -p "$T6_FAKE_HOME"
set +e
T6_OUT=$(run_get "$T6_HOME" "$T6_FAKE_HOME" "does-not-exist" 2>&1)
T6_RC=$?
set -e
if [[ "$T6_RC" == "6" ]]; then
  pass "T6 exit code 6 (download failed)"
else
  fail "T6 expected exit 6, got $T6_RC"
fi
if grep -q 'download failed' <<<"$T6_OUT"; then
  pass "T6 error mentions 'download failed'"
else
  fail "T6 error did not say 'download failed'"
fi
if grep -qE '(size=0 bytes|HTTP 404|does-not-exist)' <<<"$T6_OUT"; then
  pass "T6 error includes URL or size context"
else
  fail "T6 error missing URL/size context"
  printf '%s\n' "$T6_OUT" | sed 's/^/        /'
fi

# ============================================================================
# T7: --target=cursor passthrough
# ============================================================================
echo "[smoke-curl-install] T7 --target=cursor passthrough"
T7_HOME="$FAKE_HOME/inst-t7"
T7_FAKE_HOME="$STAGE_DIR/fake-home-t7"
mkdir -p "$T7_FAKE_HOME"
T7_RC=0
T7_OUT=$(run_get "$T7_HOME" "$T7_FAKE_HOME" "v0.3.0-test" --target=cursor 2>&1) || T7_RC=$?
if [[ "$T7_RC" == "0" ]]; then
  pass "T7 get.sh exit 0"
else
  fail "T7 get.sh exited $T7_RC"
  printf '%s\n' "$T7_OUT" | sed 's/^/        /'
fi
if [[ -L "$T7_FAKE_HOME/.cursor/skills-cursor/pensees" ]]; then
  pass "T7 cursor symlink created"
else
  fail "T7 cursor symlink missing"
fi
if [[ ! -e "$T7_FAKE_HOME/.claude/skills/pensees" \
   && ! -L "$T7_FAKE_HOME/.claude/skills/pensees" ]]; then
  pass "T7 claude symlink correctly NOT created"
else
  fail "T7 claude symlink unexpectedly created (passthrough broke)"
fi
if [[ ! -e "$T7_FAKE_HOME/.codex/skills/pensees" \
   && ! -L "$T7_FAKE_HOME/.codex/skills/pensees" ]]; then
  pass "T7 codex symlink correctly NOT created"
else
  fail "T7 codex symlink unexpectedly created (passthrough broke)"
fi

# ============================================================================
# T8: install.sh failure passes through verbatim
# ============================================================================
echo "[smoke-curl-install] T8 install.sh failure passes through"
T8_HOME="$FAKE_HOME/inst-t8"
T8_FAKE_HOME="$STAGE_DIR/fake-home-t8"
mkdir -p "$T8_FAKE_HOME"
set +e
T8_OUT=$(run_get "$T8_HOME" "$T8_FAKE_HOME" "v0.3.0-test-bad" 2>&1)
T8_RC=$?
set -e
if [[ "$T8_RC" == "42" ]]; then
  pass "T8 exit 42 (install.sh code forwarded)"
else
  fail "T8 expected exit 42, got $T8_RC"
  printf '%s\n' "$T8_OUT" | sed 's/^/        /'
fi

# --- Summary ----------------------------------------------------------------

echo
echo "[smoke-curl-install] ${pass_count} passed, ${fail_count} failed"
if (( fail_count > 0 )); then
  exit 1
fi
exit 0
