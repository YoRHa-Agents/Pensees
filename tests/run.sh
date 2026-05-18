#!/usr/bin/env bash
# tests/run.sh — Pensees gate runner.
#
# Invokes the 3 lint / smoke scripts and prints which static subset of
# HG-01..HG-13 was actually verified. HG-01..HG-04, HG-06, and HG-07 are
# inherently runtime checks — they require a real session in a host
# agent (Cursor / Claude Code / Codex) and are listed as "manual smoke
# required" at the end of the report.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Make sure the children are executable (one-off chmod is cheap and idempotent).
chmod +x tests/lint-skill.sh tests/lint-templates.sh tests/smoke-install.sh 2>/dev/null || true

overall_rc=0

run_step() {
  local label="$1"
  shift
  echo
  echo "===================================================================="
  echo " ${label}"
  echo "===================================================================="
  if "$@"; then
    echo "[${label}] PASS"
  else
    rc=$?
    echo "[${label}] FAIL (exit ${rc})"
    overall_rc=1
  fi
}

run_step "lint-skill"      tests/lint-skill.sh
run_step "lint-templates"  tests/lint-templates.sh
run_step "smoke-install"   tests/smoke-install.sh

echo
echo "===================================================================="
echo " HG coverage summary"
echo "===================================================================="

cat <<'EOF'
Static (covered by this gate when PASS):
  HG-05  single-file HTML (templates have no functional external URL)
  HG-08  HARD-GATE keyword present in SKILL.md
  HG-09  SKILL.md ≤ 250 lines
  HG-10  write-path whitelist documented in SKILL.md (presence check)
  HG-11  emergency-stop phrases present (销毁本会话 / forget this / wipe session)
  HG-12  local preview port markers present (127.0.0.1 + 8765 range)
  HG-13  option-detail probe sections present ((e) + 后果/对比/场景/未知)

Manual smoke required (cannot be verified statically — run after install):
  HG-01  Cursor autoloads the skill on trigger phrase
  HG-02  Claude Code autoloads the skill on trigger phrase
  HG-03  Codex CLI autoloads the skill on trigger phrase
  HG-04  Each finished session produces outputs/{requirements,acceptance-criteria}.md
  HG-06  Demos render fully under physical no-network
  HG-07  Each agent turn ends with at most one '?'

To run a manual smoke:
  ./install.sh                            # symlinks ./skill into all 3 targets
  # Then in each of Cursor / Claude Code / Codex CLI:
  #   send: 帮我用 pensees 想清楚一件事
  # Confirm: first turn declares Exploratory + Challenge + Convergence
  # and ends with exactly one '?'.
EOF

echo
if (( overall_rc == 0 )); then
  echo "[run] GATE PASS"
else
  echo "[run] GATE FAIL"
fi
exit "$overall_rc"
