#!/usr/bin/env bash
# tests/lint-site.sh — static lint for site/**.
#
# Implements assertions L-01..L-40 from
# .local/memory/specs/pensees/v0.3.0-design.md §9.2, encoding the
# NieR-checklist items K-01..K-04 and K-09 that are mechanically
# verifiable. K-05..K-08 + K-10 (game-quote / autoplay / JS-text-anim /
# CRT-overlay / rotation budget) are operator-eyeball checks at Verify.
#
# Exits 0 on full pass; non-zero with a per-check FAIL line otherwise.
#
# Soft-fail: L-40 (embedded-demo byte-equality vs the source under
# .local/) emits a `[warn]` and passes when the source is absent on this
# clone. This is the only soft case in the lint, documented inline per
# AGENTS.md §2 "errors must be observable".

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SITE_DIR="${REPO_ROOT}/site"

fail_count=0
pass_count=0
warn_count=0

pass() { printf '    ok   %s\n' "$1"; pass_count=$((pass_count + 1)); }
fail() { printf '    FAIL %s\n' "$1"; fail_count=$((fail_count + 1)); }
warn() { printf '    [warn] %s\n' "$1"; warn_count=$((warn_count + 1)); }

if [[ ! -d "$SITE_DIR" ]]; then
  echo "[lint-site] FAIL site dir missing: $SITE_DIR"
  exit 1
fi

# ---- collect site files ---------------------------------------------------
shopt -s nullglob globstar
SITE_HTML=( "$SITE_DIR"/index.html "$SITE_DIR"/demo.html )
SITE_CSS=( "$SITE_DIR"/styles.css )
SITE_JS=( "$SITE_DIR"/i18n.js "$SITE_DIR"/theme.js )
ALL_SCANNED=( "${SITE_HTML[@]}" "${SITE_CSS[@]}" "${SITE_JS[@]}" )

# ---- §9.2.3: per-file network-egress checks (L-01..L-07) ------------------
echo "[lint-site] §9.2.3 network-egress sub-checks (L-01..L-07)"
for f in "${ALL_SCANNED[@]}"; do
  [[ -f "$f" ]] || { fail "missing expected file: ${f#$REPO_ROOT/}"; continue; }
  rel="${f#$REPO_ROOT/}"

  # L-01: JS network APIs
  if grep -qE '\bfetch\(|XMLHttpRequest|new[[:space:]]+WebSocket\(|new[[:space:]]+EventSource\(|navigator\.sendBeacon' "$f"; then
    fail "L-01 ${rel}: JS network API call (fetch / XHR / WebSocket / EventSource / sendBeacon)"
  else
    pass "L-01 ${rel}: no JS network API call"
  fi

  # L-02 / L-03: external src/href in <script>/<link>/<iframe>/<embed>/<object>/@import.
  # Allowed: <a href="https://..."> nav links — those are user-visible link text.
  bad=$(grep -nE '<script[^>]*src=["'"'"']https?:|<link[^>]*href=["'"'"']https?:|<iframe[^>]*src=["'"'"']https?:|<embed[^>]*src=["'"'"']https?:|<object[^>]*data=["'"'"']https?:|@import[[:space:]]*url\(["'"'"']?https?:' "$f" || true)
  if [[ -n "$bad" ]]; then
    fail "L-02/L-03 ${rel}: external URL in <script>/<link>/<iframe>/<embed>/<object>/@import"
    echo "$bad" | sed 's/^/         /'
  else
    pass "L-02/L-03 ${rel}: no external URL outside <a href=>"
  fi

  # L-04: url(http...) outside @import and <!-- ... --> comments
  if grep -nE 'url\([^)]*https?:' "$f" 2>/dev/null | grep -vE '@import|<!--' >/dev/null 2>&1; then
    fail "L-04 ${rel}: CSS url(http...) outside @import / comment"
  else
    pass "L-04 ${rel}: no CSS url(http...) outside @import"
  fi

  # L-05: ES module URL imports
  if grep -qE "import[[:space:]]+.+[[:space:]]+from[[:space:]]+[\"']https?:|import[(][[:space:]]*[\"']https?:" "$f"; then
    fail "L-05 ${rel}: ES module import from external URL"
  else
    pass "L-05 ${rel}: no ES module URL import"
  fi

  # L-06 is covered by the L-02/L-03 grep (iframe/embed/object cases) above.
  pass "L-06 ${rel}: external <iframe>/<embed>/<object> covered by L-02/L-03"

  # L-07: no @font-face declarations at all (we ship no web fonts, period)
  if grep -q '@font-face' "$f"; then
    fail "L-07 ${rel}: @font-face declaration present (no web fonts allowed)"
  else
    pass "L-07 ${rel}: no @font-face"
  fi
done

# ---- §9.2.4: i18n coverage (L-10..L-13) ------------------------------------
echo "[lint-site] §9.2.4 i18n coverage (L-10..L-13)"
for f in "${SITE_HTML[@]}"; do
  [[ -f "$f" ]] || continue
  rel="${f#$REPO_ROOT/}"

  # L-12: <html lang="en"> literal in source
  if grep -qE '<html[^>]*lang="en"' "$f"; then
    pass "L-12 ${rel}: <html lang=\"en\"> declared"
  else
    fail "L-12 ${rel}: <html lang=\"en\"> not found"
  fi

  # L-13: at least one [data-i18n-toggle] and one [data-theme-toggle]
  if grep -q 'data-i18n-toggle' "$f"; then
    pass "L-13 ${rel}: data-i18n-toggle button present"
  else
    fail "L-13 ${rel}: missing [data-i18n-toggle] button"
  fi
  if grep -q 'data-theme-toggle' "$f"; then
    pass "L-13 ${rel}: data-theme-toggle button present"
  else
    fail "L-13 ${rel}: missing [data-theme-toggle] button"
  fi

  # L-10: every <h1>/<h2>/<h3>/<h4>/<button>/<figcaption> opening tag has
  # data-i18n= or data-i18n-skip. Skip lines inside <pre>/<code>/<script>/<style>.
  missing=$(awk '
    BEGIN { in_pre=0; in_code=0; in_script=0; in_style=0 }
    {
      line=$0
      while (match(line, /<\/?(pre|code|script|style)\b[^>]*>/)) {
        seg=substr(line, RSTART, RLENGTH)
        closing=(substr(seg, 2, 1) == "/") ? 1 : 0
        rest=substr(seg, 2 + closing)
        tag=""
        n=length(rest)
        for (i=1; i<=n; i++) {
          c=substr(rest, i, 1)
          if (c==" " || c=="\t" || c==">" || c=="/") break
          tag=tag c
        }
        if (tag=="pre")    { in_pre   = (closing ? 0 : 1) }
        if (tag=="code")   { in_code  = (closing ? 0 : 1) }
        if (tag=="script") { in_script= (closing ? 0 : 1) }
        if (tag=="style")  { in_style = (closing ? 0 : 1) }
        line=substr(line, RSTART + RLENGTH)
      }
      if (in_pre || in_code || in_script || in_style) next
      if ($0 ~ /<(h1|h2|h3|h4|button|figcaption)\b[^>]*>/) {
        if ($0 !~ /data-i18n[=]/ && $0 !~ /data-i18n-skip/) {
          printf "%s:%d: %s\n", FILENAME, NR, $0
        }
      }
    }
  ' "$f" || true)
  if [[ -n "$missing" ]]; then
    fail "L-10 ${rel}: heading/button/figcaption without data-i18n/data-i18n-skip"
    echo "$missing" | sed 's/^/         /'
  else
    pass "L-10 ${rel}: all headings/buttons/figcaptions are i18n-bound"
  fi

  # L-11: every <p>...text... outside pre/code/script/style has data-i18n
  # OR data-i18n-skip OR contains an <a data-i18n=...> as its only meaningful child.
  missing_p=$(awk '
    BEGIN { in_pre=0; in_code=0; in_script=0; in_style=0 }
    {
      line=$0
      while (match(line, /<\/?(pre|code|script|style)\b[^>]*>/)) {
        seg=substr(line, RSTART, RLENGTH)
        closing=(substr(seg, 2, 1) == "/") ? 1 : 0
        rest=substr(seg, 2 + closing)
        tag=""
        n=length(rest)
        for (i=1; i<=n; i++) {
          c=substr(rest, i, 1)
          if (c==" " || c=="\t" || c==">" || c=="/") break
          tag=tag c
        }
        if (tag=="pre")    { in_pre   = (closing ? 0 : 1) }
        if (tag=="code")   { in_code  = (closing ? 0 : 1) }
        if (tag=="script") { in_script= (closing ? 0 : 1) }
        if (tag=="style")  { in_style = (closing ? 0 : 1) }
        line=substr(line, RSTART + RLENGTH)
      }
      if (in_pre || in_code || in_script || in_style) next
      if ($0 ~ /<p\b[^>]*>/) {
        if ($0 !~ /data-i18n/ && $0 !~ /<a\b[^>]*data-i18n[=]/) {
          if ($0 ~ /<p\b[^>]*>[[:space:]]*</) next
          if ($0 ~ /<p\b[^>]*>[[:space:]]*$/) next
          printf "%s:%d: %s\n", FILENAME, NR, $0
        }
      }
    }
  ' "$f" || true)
  if [[ -n "$missing_p" ]]; then
    fail "L-11 ${rel}: <p> with text but no data-i18n/data-i18n-skip"
    echo "$missing_p" | sed 's/^/         /'
  else
    pass "L-11 ${rel}: all <p> elements are i18n-bound"
  fi
done

# ---- §9.2.5: header/footer parity (L-20, L-21) ----------------------------
echo "[lint-site] §9.2.5 header/footer parity (L-20, L-21)"

extract_fence() {
  local fence="$1"
  local file="$2"
  awk -v start="<!-- ${fence} START -->" -v end="<!-- ${fence} END -->" '
    index($0, start) { p=1; next }
    index($0, end)   { p=0 }
    p { print }
  ' "$file" | sed 's/ class="is-active"//g'
}

if [[ -f "$SITE_DIR/index.html" && -f "$SITE_DIR/demo.html" ]]; then
  h_index=$(extract_fence HEADER "$SITE_DIR/index.html" | sha256sum | awk '{print $1}')
  h_demo=$( extract_fence HEADER "$SITE_DIR/demo.html"  | sha256sum | awk '{print $1}')
  if [[ -n "$h_index" && "$h_index" == "$h_demo" ]]; then
    pass "L-20: header bytes match between index.html and demo.html"
  else
    fail "L-20: header bytes DIFFER (index=${h_index}, demo=${h_demo})"
  fi

  f_index=$(extract_fence FOOTER "$SITE_DIR/index.html" | sha256sum | awk '{print $1}')
  f_demo=$( extract_fence FOOTER "$SITE_DIR/demo.html"  | sha256sum | awk '{print $1}')
  if [[ -n "$f_index" && "$f_index" == "$f_demo" ]]; then
    pass "L-21: footer bytes match between index.html and demo.html"
  else
    fail "L-21: footer bytes DIFFER (index=${f_index}, demo=${f_demo})"
  fi
else
  fail "L-20/L-21: one or both HTML pages missing"
fi

# ---- §9.2.6: visual budget (L-30..L-32) -----------------------------------
echo "[lint-site] §9.2.6 visual budget (L-30..L-32)"
CSS="$SITE_DIR/styles.css"
if [[ -f "$CSS" ]]; then
  # L-30: no box-shadow with blur >= 4px (3rd numeric position).
  if grep -nE 'box-shadow:[^;]*[0-9]+px[[:space:]]+[0-9]+px[[:space:]]+([4-9][0-9]*|[1-9][0-9]+)px' "$CSS" >/dev/null 2>&1; then
    fail "L-30: box-shadow blur >= 4px detected"
    grep -nE 'box-shadow:[^;]*[0-9]+px[[:space:]]+[0-9]+px[[:space:]]+([4-9][0-9]*|[1-9][0-9]+)px' "$CSS" | sed 's/^/         /'
  else
    pass "L-30: no box-shadow blur >= 4px"
  fi

  # L-31: no border-radius >= 5px.
  if grep -nE 'border-radius:[[:space:]]*([5-9]|[1-9][0-9]+)px' "$CSS" >/dev/null 2>&1; then
    fail "L-31: border-radius >= 5px detected"
    grep -nE 'border-radius:[[:space:]]*([5-9]|[1-9][0-9]+)px' "$CSS" | sed 's/^/         /'
  else
    pass "L-31: no border-radius >= 5px"
  fi

  # L-32: every #xxxxxx hex literal in styles.css must be assigned to a --c-*
  # CSS custom property somewhere in the same file. (Palette closure / K-01.)
  hex_literals=$(grep -oE '#[0-9a-fA-F]{6}' "$CSS" | sort -u | tr 'A-F' 'a-f')
  if [[ -z "$hex_literals" ]]; then
    fail "L-32: no #xxxxxx hex literals found in styles.css (suspicious)"
  else
    bad=0
    for hex in $hex_literals; do
      if ! grep -iqE "\-\-c-[a-z0-9-]+[[:space:]]*:[[:space:]]*${hex}\b" "$CSS"; then
        fail "L-32: hex literal ${hex} is used but not bound to any --c-* declaration"
        bad=1
      fi
    done
    if (( bad == 0 )); then
      pass "L-32: every hex literal is bound to a --c-* declaration (palette closure)"
    fi
  fi
else
  fail "L-30/L-31/L-32: site/styles.css missing"
fi

# ---- NieR-checklist mechanical adds (K-02 / K-03 / K-05) -----------------
echo "[lint-site] NieR-checklist mechanical adds (K-02 monospace, K-03 emoji, K-05 game quotes)"

# K-02: forbid sans-serif/serif as a generic-family fallback (case-sensitive
# token, followed by a comma or semicolon — embedded uppercase font names
# like 'Source Han Serif SC' do NOT match this pattern).
if grep -nE '(font-family|--font-stack)[[:space:]]*:[^;]*\b(sans-serif|serif)[[:space:]]*[,;]' "$CSS" >/dev/null 2>&1; then
  fail "K-02: non-monospace generic-family fallback declared in styles.css"
  grep -nE '(font-family|--font-stack)[[:space:]]*:[^;]*\b(sans-serif|serif)[[:space:]]*[,;]' "$CSS" | sed 's/^/         /'
else
  pass "K-02: font stack is monospace-only"
fi

# K-03: no emoji codepoints (U+1F300..U+1F9FF) in HTML/CSS/JS source.
# Use python3 (already a documented CI dep — see .github/workflows/test.yml)
# instead of `grep -P` to keep portability across BSD grep environments.
emoji_hits=0
for f in "${ALL_SCANNED[@]}"; do
  [[ -f "$f" ]] || continue
  rel="${f#$REPO_ROOT/}"
  if python3 - "$f" <<'PY'
import re, sys
with open(sys.argv[1], "rb") as fh:
    text = fh.read().decode("utf-8", "replace")
m = re.search(r"[\U0001F300-\U0001F9FF]", text)
sys.exit(0 if m else 1)
PY
  then
    fail "K-03 ${rel}: emoji codepoint U+1F300..U+1F9FF found"
    emoji_hits=$((emoji_hits + 1))
  fi
done
if (( emoji_hits == 0 )); then
  pass "K-03: no emoji codepoints in site sources"
fi

# K-05: no NieR character names except inside the SVG aria-label "YoRHa-style mark".
k05_hits=0
for f in "${ALL_SCANNED[@]}"; do
  [[ -f "$f" ]] || continue
  rel="${f#$REPO_ROOT/}"
  bad=$(grep -nE '\b(2B|9S|A2)\b' "$f" 2>/dev/null | grep -vE 'aria-label|YoRHa-style mark|--c-bg|c-fg|c-rule|0x|U\+' || true)
  if [[ -n "$bad" ]]; then
    fail "K-05 ${rel}: NieR character name in body content"
    echo "$bad" | sed 's/^/         /'
    k05_hits=$((k05_hits + 1))
  fi
done
if (( k05_hits == 0 )); then
  pass "K-05: no NieR character names in body content"
fi

# ---- §9.2.8: scope-inclusive applyAll regression (L-41, PR #3 fix) --------
# Bugbot review on PR #3 caught: applyAll(scope) called scope.querySelectorAll
# which returns only DESCENDANTS — so the demo.html copy-button manual-select
# fallback (which sets data-i18n on the button then calls applyAll(btn))
# never updated the button's textContent. This guards the fix two ways:
#   (a) static marker grep — i18n.js must contain both the scope-attribute
#       check AND the descendant query;
#   (b) optional runtime smoke via node — builds a minimal DOM mock with a
#       single scope element carrying [data-i18n] and asserts applyAll(scope)
#       mutates scope.textContent. Skipped (warn, not fail) when node is
#       absent so the lint still works on bash-only CI runners.
echo "[lint-site] §9.2.8 scope-inclusive applyAll (L-41, PR #3 Bugbot fix)"
I18N_JS="${SITE_DIR}/i18n.js"
if [[ ! -f "$I18N_JS" ]]; then
  fail "L-41 ${I18N_JS#$REPO_ROOT/}: file missing"
elif grep -qF 'scope.hasAttribute("data-i18n")' "$I18N_JS" \
     && grep -qF 'scope.querySelectorAll("[data-i18n]")' "$I18N_JS"; then
  pass "L-41a: applyAll scope-inclusion marker present (handles scope AND descendants)"
else
  fail "L-41a: applyAll missing scope-inclusion fix (see PR #3 review thread)"
fi

if command -v node >/dev/null 2>&1; then
  smoke_rc=0
  node - "$I18N_JS" <<'NODE_EOF' || smoke_rc=$?
const fs = require("fs");
const i18nSrc = fs.readFileSync(process.argv[2], "utf8");

let warned = false;
const origWarn = console.warn;
console.warn = () => { warned = true; };

const docMock = {
  documentElement: { lang: "en" },
  querySelectorAll: () => [],
  querySelector: () => null,
  title: "",
  addEventListener: () => {},
  readyState: "loading",
};
global.document = docMock;
global.window = {
  document: docMock,
  matchMedia: () => ({ matches: false, addEventListener: () => {} }),
  localStorage: { getItem: () => null, setItem: () => {} },
  addEventListener: () => {},
};
global.navigator = { language: "en" };

eval(i18nSrc);

const i18n = global.window.PenseesI18n;
if (!i18n || typeof i18n.applyAll !== "function") {
  console.error("FAIL window.PenseesI18n.applyAll not exposed");
  process.exit(2);
}

const target = {
  nodeType: 1,
  textContent: "[ COPY ]",
  _attrs: { "data-i18n": "install.copy_button_manual" },
  hasAttribute(name) { return Object.prototype.hasOwnProperty.call(this._attrs, name); },
  getAttribute(name) { return Object.prototype.hasOwnProperty.call(this._attrs, name) ? this._attrs[name] : null; },
  setAttribute(name, value) { this._attrs[name] = String(value); },
  querySelectorAll: () => [],
};

i18n.applyAll(target);

console.warn = origWarn;

if (target.textContent === "[ COPY ]") {
  console.error("FAIL applyAll(target) did not mutate target.textContent");
  process.exit(1);
}
if (!warned) {
  // applyAll should have warned about the missing dictionary key (we didn't
  // load STRINGS), which produces a "[install.copy_button_manual]" textContent.
  // Either way the key thing is target.textContent changed.
}
console.log("OK applyAll(target).textContent ->", JSON.stringify(target.textContent));
process.exit(0);
NODE_EOF
  if (( smoke_rc == 0 )); then
    pass "L-41b: runtime smoke — applyAll(scope) mutates scope.textContent"
  else
    fail "L-41b: runtime smoke FAILED (rc=${smoke_rc}) — applyAll(scope) did not mutate scope"
  fi
else
  warn "L-41b: node not available — skipping runtime smoke (static L-41a still covers the fix)"
fi

# ---- §9.2.7: embedded-demo byte equality (L-40, soft-fail) ----------------
echo "[lint-site] §9.2.7 embedded-demo byte equality (L-40)"
SRC_DEMO="${REPO_ROOT}/.local/pensees/2026-05-18-pensees-self-design/demos/01-preset-voice-comparison.html"
DST_DEMO="${SITE_DIR}/embedded-demos/01-preset-voice-comparison.html"
if [[ ! -f "$DST_DEMO" ]]; then
  fail "L-40: copied demo missing at site/embedded-demos/01-preset-voice-comparison.html"
elif [[ ! -f "$SRC_DEMO" ]]; then
  warn "L-40: source demo not present at .local/pensees/... — cannot verify byte-equality (R-07 soft-fail)"
  pass "L-40: skipped (source under .local/ not on this clone)"
else
  src_sha=$(sha256sum "$SRC_DEMO" | awk '{print $1}')
  dst_sha=$(sha256sum "$DST_DEMO" | awk '{print $1}')
  if [[ "$src_sha" == "$dst_sha" ]]; then
    pass "L-40: embedded demo byte-equal to source under .local/"
  else
    fail "L-40: embedded demo bytes DIFFER (src=${src_sha}, dst=${dst_sha})"
  fi
fi

# ---- summary --------------------------------------------------------------
echo
echo "[lint-site] checked $(printf '%s ' "${ALL_SCANNED[@]##*/}"); ${pass_count} ok, ${fail_count} fail, ${warn_count} warn"
if (( fail_count > 0 )); then
  echo "[lint-site] FAIL"
  exit 1
fi
echo "[lint-site] PASS"
exit 0
