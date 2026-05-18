#!/usr/bin/env bash
# tests/smoke-install.sh — end-to-end smoke for install.sh.
#
# Uses mktemp -d to simulate a fake $HOME and a fake --workspace path.
# Exercises: default install (3 targets), idempotency, --uninstall,
# --workspace, and --dry-run. Verifies symlink targets resolve back to
# our source skill/ directory.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL="${REPO_ROOT}/install.sh"
SOURCE_DIR="${REPO_ROOT}/skill"

fail_count=0
pass_count=0

pass() { printf '  ok   %s\n' "$1"; pass_count=$((pass_count + 1)); }
fail() { printf '  FAIL %s\n' "$1"; fail_count=$((fail_count + 1)); }

# --- Pre-flight ---------------------------------------------------------------

if [[ ! -x "$INSTALL" ]]; then
  echo "[smoke-install] FAIL install.sh missing or not executable: $INSTALL"
  exit 1
fi
if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "[smoke-install] FAIL source skill/ missing: $SOURCE_DIR"
  exit 1
fi

# --- Setup fake $HOME + workspace --------------------------------------------

FAKE_HOME="$(mktemp -d -t pensees-smoke-home-XXXX)"
FAKE_WS="$(mktemp -d -t pensees-smoke-ws-XXXX)"
trap 'rm -rf "$FAKE_HOME" "$FAKE_WS"' EXIT

echo "[smoke-install] fake HOME = $FAKE_HOME"
echo "[smoke-install] fake WS   = $FAKE_WS"

# Subshells so we can override HOME without leaking into the parent.
run_install() {
  ( cd "$REPO_ROOT" && HOME="$FAKE_HOME" "$INSTALL" "$@" )
}

# --- Test 1: default install creates 3 symlinks to our source ----------------

echo "[smoke-install] T1 default install"
run_install >/dev/null

EXPECTED=(
  "$FAKE_HOME/.cursor/skills-cursor/pensees"
  "$FAKE_HOME/.claude/skills/pensees"
  "$FAKE_HOME/.codex/skills/pensees"
)
for p in "${EXPECTED[@]}"; do
  if [[ -L "$p" ]]; then
    actual="$(readlink "$p")"
    if [[ "$actual" == "$SOURCE_DIR" ]]; then
      pass "T1 symlink ok: ${p#$FAKE_HOME/}"
    else
      fail "T1 symlink wrong target: $p -> $actual (expected $SOURCE_DIR)"
    fi
  else
    fail "T1 missing symlink: $p"
  fi
done

# --- Test 2: rerun is idempotent (no errors, links unchanged) ----------------

echo "[smoke-install] T2 idempotent rerun"
if out2=$(run_install 2>&1); then
  if printf '%s\n' "$out2" | grep -q '^\[skip\] cursor already linked'; then
    pass "T2 rerun reported [skip] (idempotent)"
  else
    fail "T2 rerun did not emit [skip] line — output: $out2"
  fi
else
  fail "T2 rerun returned non-zero"
fi

# --- Test 3: --uninstall removes all 3 links ---------------------------------

echo "[smoke-install] T3 --uninstall"
run_install --uninstall >/dev/null
for p in "${EXPECTED[@]}"; do
  if [[ -e "$p" || -L "$p" ]]; then
    fail "T3 still present after --uninstall: $p"
  else
    pass "T3 removed: ${p#$FAKE_HOME/}"
  fi
done

# --- Test 4: --workspace places links under PATH ----------------------------

echo "[smoke-install] T4 --workspace install"
run_install --workspace "$FAKE_WS" >/dev/null
WS_EXPECTED=(
  "$FAKE_WS/.cursor/skills-cursor/pensees"
  "$FAKE_WS/.claude/skills/pensees"
  "$FAKE_WS/.codex/skills/pensees"
)
for p in "${WS_EXPECTED[@]}"; do
  if [[ -L "$p" ]] && [[ "$(readlink "$p")" == "$SOURCE_DIR" ]]; then
    pass "T4 workspace symlink ok: ${p#$FAKE_WS/}"
  else
    fail "T4 workspace symlink missing or wrong: $p"
  fi
done

# Confirm fake $HOME was not touched by --workspace.
for p in "${EXPECTED[@]}"; do
  if [[ -e "$p" || -L "$p" ]]; then
    fail "T4 fake HOME was touched by --workspace install: $p"
  fi
done
pass "T4 fake HOME untouched by --workspace install"

# --- Test 5: --dry-run is non-destructive ----------------------------------

echo "[smoke-install] T5 --dry-run"
# First clean the workspace tree from T4 by uninstalling.
run_install --workspace "$FAKE_WS" --uninstall >/dev/null

# Snapshot fake HOME before dry-run
before_listing=$(find "$FAKE_HOME" 2>/dev/null | sort || true)
run_install --dry-run >/dev/null
after_listing=$(find "$FAKE_HOME" 2>/dev/null | sort || true)
if [[ "$before_listing" == "$after_listing" ]]; then
  pass "T5 --dry-run did not modify fake HOME"
else
  fail "T5 --dry-run modified fake HOME"
fi

# --- Test 6: missing source dir → loud failure -------------------------------

echo "[smoke-install] T6 missing source skill/ → exit non-zero"
TMP_REPO="$(mktemp -d -t pensees-smoke-norepo-XXXX)"
cp "$INSTALL" "$TMP_REPO/install.sh"
chmod +x "$TMP_REPO/install.sh"
# Note: no skill/ dir was copied
if HOME="$FAKE_HOME" "$TMP_REPO/install.sh" >/dev/null 2>&1; then
  fail "T6 install.sh succeeded with missing source — should have failed"
else
  pass "T6 install.sh exited non-zero with missing source (no silent fallback)"
fi
rm -rf "$TMP_REPO"

# --- summary ----------------------------------------------------------------

echo "[smoke-install] ${pass_count} passed, ${fail_count} failed"
if (( fail_count > 0 )); then
  exit 1
fi
exit 0
