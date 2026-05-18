#!/usr/bin/env bash
# tests/lint-templates.sh — static lint for skill/templates/*.html.
#
# Covers HG-05 (single-file HTML, no external functional URLs) and the
# visibly-rough aesthetic spec from F-19 / requirements.md §7.3.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATES_DIR="${REPO_ROOT}/skill/templates"

fail_count=0
pass_count=0
files_checked=0

pass() { printf '    ok   %s\n' "$1"; pass_count=$((pass_count + 1)); }
fail() { printf '    FAIL %s\n' "$1"; fail_count=$((fail_count + 1)); }

if [[ ! -d "$TEMPLATES_DIR" ]]; then
  echo "[lint-templates] FAIL templates dir missing: $TEMPLATES_DIR"
  exit 1
fi

for tpl in "$TEMPLATES_DIR"/*.html; do
  files_checked=$((files_checked + 1))
  name="${tpl##*/}"
  echo "[lint-templates] ${name}"

  # F-20 anchor placeholder
  if grep -q "pensees-anchor" "$tpl"; then
    pass "F-20 anchor placeholder present"
  else
    fail "F-20 missing 'pensees-anchor' comment"
  fi

  # F-17 candidate meta tag
  if grep -q '<meta name="pensees-candidate"' "$tpl"; then
    pass "F-17 pensees-candidate meta tag present"
  else
    fail "F-17 missing <meta name=\"pensees-candidate\">"
  fi

  # F-19 banner
  if grep -q "DRAFT — please critique" "$tpl"; then
    pass "F-19 DRAFT banner present"
  else
    fail "F-19 missing 'DRAFT — please critique' banner"
  fi

  # F-19 dashed border
  if grep -q "dashed" "$tpl"; then
    pass "F-19 dashed border style present"
  else
    fail "F-19 no 'dashed' style declaration"
  fi

  # F-19 rough font family
  if grep -qE "cursive|Comic|Caveat|Excalifont" "$tpl"; then
    pass "F-19 rough font family present"
  else
    fail "F-19 missing handwriting / cursive font family"
  fi

  # F-19 TODO comment
  if grep -q "<!-- TODO" "$tpl"; then
    pass "F-19 TODO comment present"
  else
    fail "F-19 no <!-- TODO --> comment"
  fi

  # F-15 / HG-05: no functional external URLs
  # Allowed: https?:// inside HTML comments (<!-- ... --> spanning the line).
  # Disallowed: src="https?:, href="https?:, @import url(https?:
  if grep -qE 'src="https?:|href="https?:|@import url\(https?:' "$tpl"; then
    fail "HG-05 functional external URL found (src/href/@import)"
  else
    pass "HG-05 no functional external URL"
  fi
done

if (( files_checked == 0 )); then
  echo "[lint-templates] FAIL no .html templates found under $TEMPLATES_DIR"
  exit 1
fi

# Also lint the demo-decision-tree.md reference for HG-05-relevant guidance.
echo "[lint-templates] checked ${files_checked} files; ${pass_count} ok, ${fail_count} fail"
if (( fail_count > 0 )); then
  exit 1
fi
exit 0
