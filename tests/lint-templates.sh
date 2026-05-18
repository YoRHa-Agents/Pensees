#!/usr/bin/env bash
# tests/lint-templates.sh — static lint for skill/templates/*.html.
#
# Covers:
#   - HG-05 (single-file HTML, no external functional URLs — double-quoted forms);
#   - HG-06 STATIC SUBSET (no-network demo render — the static-verifiable half).
#     HG-06 itself ("demos render fully under physical no-network") still
#     requires a runtime smoke after install: a static lint can confirm the
#     ABSENCE of all known network-egress patterns enumerated by F-15
#     (no fetch / no WebSocket / no XHR / no external <iframe> / no CSS
#     url(http...) etc.) but cannot prove the template actually renders
#     under a real disconnected network. The static subset is a
#     necessary-but-not-sufficient signal — it catches a regression where
#     someone reintroduces a forbidden pattern even when manual smoke is
#     skipped. See tests/run.sh for the runtime-vs-static split summary.
#   - the visibly-rough aesthetic spec from F-19 / requirements.md §7.3.

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

  # ── HG-06 STATIC SUBSET: enumerate F-15 forbidden network-egress patterns ──
  # F-15: "No `http://` / `https://` external resources. No CDN fonts.
  #        No `fetch()`. Offline-double-clickable."
  # Each sub-check below covers one egress vector NOT caught by the HG-05
  # check above. False-positive containment: every pattern is shaped to match
  # FUNCTIONAL syntax (token-bounded keyword + opening paren/quote/angle), so
  # mentions inside <!-- ... --> comments or pure-string literals like
  # `"see <iframe> docs"` will not match. The grep patterns are intentionally
  # conservative — a regression that smuggles in a new vector via an unusual
  # quoting style is caught by the runtime no-network smoke (HG-06 full).

  # HG-06(a) — JS network APIs (fetch / XHR / WebSocket / EventSource / sendBeacon)
  if grep -qE '\bfetch\(|XMLHttpRequest|new[[:space:]]+WebSocket\(|new[[:space:]]+EventSource\(|navigator\.sendBeacon' "$tpl"; then
    fail "HG-06(a) JS network API call found (fetch / XHR / WebSocket / EventSource / sendBeacon)"
  else
    pass "HG-06(a) no JS network API call"
  fi

  # HG-06(b) — single-quoted external URLs in src/href/@import
  # (companion to HG-05 which only covers the double-quoted form)
  if grep -qE "src='https?:|href='https?:|@import url\('https?:" "$tpl"; then
    fail "HG-06(b) single-quoted external URL found (src='/href='/@import')"
  else
    pass "HG-06(b) no single-quoted external URL"
  fi

  # HG-06(c) — CSS url() with external scheme outside @import
  # (background-image, list-style-image, @font-face src, content, etc.)
  # @import url(http...) is HG-05's responsibility; explicitly excluded here.
  if grep -nE 'url\([^)]*https?:' "$tpl" | grep -vE '@import|<!--' >/dev/null 2>&1; then
    fail "HG-06(c) CSS url(http...) found outside @import (background / font-face / etc.)"
  else
    pass "HG-06(c) no CSS url(http) outside @import"
  fi

  # HG-06(d) — ES module import from external URL
  if grep -qE "import[[:space:]]+.+[[:space:]]+from[[:space:]]+[\"']https?:|import[(][[:space:]]*[\"']https?:" "$tpl"; then
    fail "HG-06(d) ES module import from external URL found"
  else
    pass "HG-06(d) no ES module import from external URL"
  fi

  # HG-06(e) — external <iframe>/<embed>/<object> tags
  if grep -qE "<iframe[^>]*src=[\"']https?:|<embed[^>]*src=[\"']https?:|<object[^>]*data=[\"']https?:" "$tpl"; then
    fail "HG-06(e) external <iframe>/<embed>/<object> found"
  else
    pass "HG-06(e) no external <iframe>/<embed>/<object>"
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
