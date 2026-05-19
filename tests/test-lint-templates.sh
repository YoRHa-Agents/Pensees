#!/usr/bin/env bash
# tests/test-lint-templates.sh — META-TEST for the HG-06 sub-checks added
# to tests/lint-templates.sh in commit 037ff7f.
#
# AGENTS.md §"Mandatory Verification" requires every new logic to ship with
# its own test. The HG-06 sub-checks are pure greps with combined patterns
# — easy to get wrong. This script is the unit test:
#
#   Positive case: the lint MUST exit 0 on the unmodified skill/templates/
#                  (baseline regression guard).
#   Negative case: for EACH of the 7 enumerated forbidden patterns (one per
#                  HG-06 sub-check + 2 extra JS API variants), the lint MUST
#                  exit non-zero AND the FAIL line MUST name the right
#                  sub-check (HG-06(a) / (b) / (c) / (d) / (e)).
#
# Why this is needed beyond the one-shot negative_smoke captured at round 1:
# the next contributor who edits tests/lint-templates.sh will run THIS
# script to confirm they didn't accidentally weaken the regex. The
# round-1 raw/negative_smoke.txt was a one-off proof; this is the
# permanent regression test.
#
# Exit codes: 0 = lint behaves correctly on all 8 cases; 1 = at least one
# behavior mismatch.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LINT="${REPO_ROOT}/tests/lint-templates.sh"
TEMPLATE_DIR_SRC="${REPO_ROOT}/skill/templates"
TARGET_TEMPLATE="demo-explorable.html"

fail_count=0
pass_count=0

pass() { printf '  ok   %s\n' "$1"; pass_count=$((pass_count + 1)); }
fail() { printf '  FAIL %s\n' "$1"; fail_count=$((fail_count + 1)); }

if [[ ! -x "$LINT" ]]; then
  echo "[test-lint-templates] FAIL lint-templates.sh missing or not executable: $LINT"
  exit 1
fi
if [[ ! -d "$TEMPLATE_DIR_SRC" ]]; then
  echo "[test-lint-templates] FAIL templates source missing: $TEMPLATE_DIR_SRC"
  exit 1
fi

echo "[test-lint-templates] meta-testing ${LINT}"

# --- Positive case: unmodified templates --------------------------------------
TMP_POS="$(mktemp -d -t pensees-test-lint-pos-XXXX)"
cp -r "${REPO_ROOT}/skill" "${TMP_POS}/skill"
# Build a patched lint script that points at our temp skill/templates/.
sed "s|REPO_ROOT=.*|REPO_ROOT=\"${TMP_POS}\"|" "$LINT" > "${TMP_POS}/lint.sh"
chmod +x "${TMP_POS}/lint.sh"
if bash "${TMP_POS}/lint.sh" >"${TMP_POS}/out.txt" 2>&1; then
  pass "positive case: lint exits 0 on unmodified templates"
else
  rc=$?
  fail "positive case: lint exited ${rc} on unmodified templates (regression)"
  tail -5 "${TMP_POS}/out.txt" | sed 's/^/      /'
fi
rm -rf "$TMP_POS"

# --- Negative cases: one injection per HG-06 sub-check ------------------------
# Each tuple: <label> <expected_pattern_in_FAIL_line> <injection_html_snippet>
declare -a CASES=(
  "HG-06(a)-fetch         |HG-06\(a\)|<script>fetch('http://evil.example/x');</script>"
  "HG-06(a)-WebSocket     |HG-06\(a\)|<script>const s = new WebSocket('ws://evil');</script>"
  "HG-06(a)-XMLHttpReq    |HG-06\(a\)|<script>const x = new XMLHttpRequest();</script>"
  "HG-06(b)-singlequote   |HG-06\(b\)|<a href='http://evil/'>link</a>"
  "HG-06(c)-css-url       |HG-06\(c\)|<style>body{background:url(http://evil/bg.png)}</style>"
  "HG-06(d)-es-module     |HG-06\(d\)|<script type='module'>import x from 'https://evil/lib.js';</script>"
  "HG-06(e)-iframe        |HG-06\(e\)|<iframe src=\"http://evil\"></iframe>"
)

for case_spec in "${CASES[@]}"; do
  IFS='|' read -r label expected_pattern injection <<< "$case_spec"
  label="$(printf '%s' "$label" | sed 's/[[:space:]]*$//')"

  TMP_NEG="$(mktemp -d -t pensees-test-lint-neg-XXXX)"
  cp -r "${REPO_ROOT}/skill" "${TMP_NEG}/skill"
  # Inject the forbidden snippet into the target template just before </body>.
  if grep -q '</body>' "${TMP_NEG}/skill/templates/${TARGET_TEMPLATE}"; then
    awk -v inj="$injection" '
      /<\/body>/ { print inj; print; next }
      { print }
    ' "${TMP_NEG}/skill/templates/${TARGET_TEMPLATE}" > "${TMP_NEG}/skill/templates/${TARGET_TEMPLATE}.new"
    mv "${TMP_NEG}/skill/templates/${TARGET_TEMPLATE}.new" "${TMP_NEG}/skill/templates/${TARGET_TEMPLATE}"
  else
    printf '\n%s\n' "$injection" >> "${TMP_NEG}/skill/templates/${TARGET_TEMPLATE}"
  fi

  sed "s|REPO_ROOT=.*|REPO_ROOT=\"${TMP_NEG}\"|" "$LINT" > "${TMP_NEG}/lint.sh"
  chmod +x "${TMP_NEG}/lint.sh"
  if bash "${TMP_NEG}/lint.sh" >"${TMP_NEG}/out.txt" 2>&1; then
    fail "${label}: lint accepted forbidden pattern (expected non-zero exit)"
    tail -5 "${TMP_NEG}/out.txt" | sed 's/^/      /'
  else
    # Confirm the FAIL line names the right sub-check.
    if grep -qE "FAIL.*${expected_pattern}" "${TMP_NEG}/out.txt"; then
      pass "${label}: lint rejected with expected sub-check"
    else
      fail "${label}: lint rejected but FAIL line did not name ${expected_pattern}"
      grep -E '^[[:space:]]*FAIL' "${TMP_NEG}/out.txt" | head -5 | sed 's/^/      /'
    fi
  fi
  rm -rf "$TMP_NEG"
done

# --- summary -----------------------------------------------------------------
echo "[test-lint-templates] ${pass_count} passed, ${fail_count} failed"
if (( fail_count > 0 )); then
  exit 1
fi
exit 0
