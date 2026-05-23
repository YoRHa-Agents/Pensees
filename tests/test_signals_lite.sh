#!/usr/bin/env bash
# tests/test_signals_lite.sh — end-to-end check of the Lite scorer + offline
# reviewer CLI on three hand-curated `turns.jsonl` fixtures.
#
# Each fixture under tests/fixtures/v032/ is a 6+ turn Lite session matching
# the schema in skill/references/intermediate-result-schema.md plus the
# signal definitions in skill/references/composite-signals.md. They are
# crafted to land on a specific reviewer verdict:
#
#   premature_positive  → composite_premature peaks ≥ 0.6 on the last turn
#                          (slot_focus_imbalance + e_probe_over_use +
#                          question_form_jump all fire). Expected verdict:
#                          one of {flagged, high-friction}.
#   dead_end_positive   → composite_dead_end peaks ≥ 0.65 on the last turn
#                          (amnesia + dimension_repetition + frame_collapse
#                          + checklist_regression all fire). Expected
#                          verdict: one of {flagged, high-friction}.
#   all_clean           → both composites stay < 0.6 for every turn.
#                          Expected verdict: clean.
#
# Each group T-PREM-POS / T-DEAD-POS / T-CLEAN:
#   1. clears any leftover review.md from the fixture dir (so the run is
#      reproducible across machines + across multiple gate runs),
#   2. invokes `python3 tools/pensees_review.py <fixture>/`,
#   3. asserts exit code 0,
#   4. asserts the produced review.md exists and is non-empty,
#   5. asserts the rendered `Verdict: ` line matches the expected enum,
#   6. cleans up the produced review.md (also gitignored by `.gitignore`).
#
# Failure interpretation: a single FAIL line names the group + assertion.
# If the verdict line is wrong, the fixture data drifted away from the
# threshold envelope — recompute the expected raw signals using the
# pseudocode in composite-signals.md before editing the JSONL.
#
# Exit codes: 0 = all three groups passed; 1 = at least one group failed.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

fail_count=0
pass_count=0

pass() { printf '  ok   %s\n' "$1"; pass_count=$((pass_count + 1)); }
fail() { printf '  FAIL %s\n' "$1"; fail_count=$((fail_count + 1)); }

echo "[test-signals-lite] running offline reviewer against 3 fixtures from ${REPO_ROOT}"

# run_group <label> <fixture-subdir> <expected-verdict-regex>
# Expected-verdict-regex is matched against the value inside the backticks on
# the rendered `Verdict: ` line. Examples:
#   ^(flagged|high-friction)$   premature / dead-end positive cases
#   ^clean$                     all_clean case
run_group() {
  local label="$1"
  local fixture="$2"
  local expected_re="$3"
  local fixture_dir="tests/fixtures/v032/${fixture}"
  local review_path="${fixture_dir}/review.md"

  rm -f "$review_path"

  local cli_rc
  python3 tools/pensees_review.py "${fixture_dir}/" >/dev/null
  cli_rc=$?

  if (( cli_rc == 0 )); then
    pass "${label} CLI exit 0 on '${fixture_dir}/'"
  else
    fail "${label} CLI exited ${cli_rc} on '${fixture_dir}/' (expected 0)"
    return
  fi

  if [[ -s "$review_path" ]]; then
    pass "${label} review.md exists and is non-empty at '${review_path}'"
  else
    fail "${label} review.md missing or empty at '${review_path}'"
    return
  fi

  local verdict_line
  verdict_line=$(grep -E '^Verdict: ' "$review_path" || true)
  if [[ -z "$verdict_line" ]]; then
    fail "${label} 'Verdict: ' line not found in '${review_path}'"
    rm -f "$review_path"
    return
  fi

  local verdict_value
  verdict_value=$(printf '%s\n' "$verdict_line" | sed -E 's/^Verdict: `([^`]+)`.*$/\1/')

  if [[ "$verdict_value" =~ $expected_re ]]; then
    pass "${label} verdict='${verdict_value}' matches /${expected_re}/"
  else
    fail "${label} verdict='${verdict_value}' does NOT match /${expected_re}/"
  fi

  rm -f "$review_path"
}

run_group "T-PREM-POS" "premature_positive" '^(flagged|high-friction)$'
run_group "T-DEAD-POS" "dead_end_positive"  '^(flagged|high-friction)$'
run_group "T-CLEAN"    "all_clean"          '^clean$'

echo "[test-signals-lite] ${pass_count} passed, ${fail_count} failed"
if (( fail_count > 0 )); then
  exit 1
fi
exit 0
