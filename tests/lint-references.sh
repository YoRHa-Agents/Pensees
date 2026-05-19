#!/usr/bin/env bash
# tests/lint-references.sh — extends the HG-06 network-egress scan to
# skill/references/*.md and skill/examples/*.md.
#
# The original HG-06 static subset in tests/lint-templates.sh only scans
# skill/templates/*.html. But the reference docs and worked-example sessions
# can themselves embed HTML / JS / CSS code blocks (e.g., a question-form
# reference might illustrate a button with inline <script>). A regression
# that smuggles a forbidden network-egress pattern into one of those code
# blocks would propagate into the skill bundle without being caught.
#
# Scope: enforce the same F-15 forbidden patterns ONLY inside fenced code
# blocks tagged html / js / javascript / ts / typescript / css. Prose lines
# are NOT scanned — a reference doc can legitimately write "don't use
# `fetch()`" in body text without tripping the lint. This is the same
# trade-off the existing lint-transcript.sh makes (in-fence content is
# special-cased).
#
# Coverage:
#   HG-06(*) — same five sub-checks as lint-templates.sh, applied to every
#              relevant fenced code block in references/ + examples/.
#
# Exit codes: 0 = all blocks clean; 1 = at least one forbidden pattern found.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REF_DIR="${REPO_ROOT}/skill/references"
EX_DIR="${REPO_ROOT}/skill/examples"

fail_count=0
pass_count=0
blocks_scanned=0

pass() { printf '    ok   %s\n' "$1"; pass_count=$((pass_count + 1)); }
fail() { printf '    FAIL %s\n' "$1"; fail_count=$((fail_count + 1)); }

# extract_blocks <file>
#   stream the fenced code blocks tagged html/js/javascript/ts/typescript/css
#   to a temp file, prefixed with `FILE:LINE | `. We can then grep the temp
#   file with the same patterns lint-templates.sh uses.
extract_blocks() {
  local file="$1" out="$2"
  awk -v F="$file" '
    BEGIN { in_block = 0; block_kind = "" }
    /^```(html|js|javascript|ts|typescript|css)[[:space:]]*$/ {
      in_block = 1
      block_kind = $0
      sub(/^```/, "", block_kind)
      block_start_line = NR
      block_lines = 0
      next
    }
    /^```[[:space:]]*$/ {
      if (in_block) {
        printf("META: end block kind=%s file=%s start=%d end=%d lines=%d\n",
               block_kind, F, block_start_line, NR, block_lines)
        in_block = 0
        block_kind = ""
      }
      next
    }
    in_block {
      block_lines++
      printf("%s:%d: %s\n", F, NR, $0)
    }
  ' "$file" >> "$out"
}

mds=()
for d in "$REF_DIR" "$EX_DIR"; do
  if [[ -d "$d" ]]; then
    while IFS= read -r -d '' f; do
      mds+=("$f")
    done < <(find "$d" -name '*.md' -print0 | LC_ALL=C sort -z)
  fi
done

if (( ${#mds[@]} == 0 )); then
  echo "[lint-references] FAIL no markdown files found under $REF_DIR or $EX_DIR"
  exit 1
fi

TMP_BLOCKS="$(mktemp -t pensees-ref-blocks-XXXX.txt)"
trap 'rm -f "$TMP_BLOCKS"' EXIT

for f in "${mds[@]}"; do
  : > /tmp/.lint-ref-this.$$
  extract_blocks "$f" /tmp/.lint-ref-this.$$
  blocks_in_file=$(grep -c '^META: end block' /tmp/.lint-ref-this.$$ || true)
  if (( blocks_in_file > 0 )); then
    echo "[lint-references] ${f##${REPO_ROOT}/}: ${blocks_in_file} html/js/css code block(s)"
    blocks_scanned=$((blocks_scanned + blocks_in_file))
    cat /tmp/.lint-ref-this.$$ >> "$TMP_BLOCKS"
  fi
  rm -f /tmp/.lint-ref-this.$$
done

if (( blocks_scanned == 0 )); then
  echo "[lint-references] 0 html/js/css code blocks found — nothing to scan (this is OK)"
  echo "[lint-references] 0 checks run, 0 failed"
  exit 0
fi

# Same five HG-06 patterns as lint-templates.sh.
# We grep against TMP_BLOCKS which contains ONLY in-fence content prefixed
# with `FILE:LINE | `, plus `META: ...` framing lines (we exclude those).
SCAN="$(grep -v '^META:' "$TMP_BLOCKS" || true)"

scan_pattern() {
  local label="$1" pattern="$2"
  local hits
  hits="$(printf '%s\n' "$SCAN" | grep -E "$pattern" || true)"
  if [[ -z "$hits" ]]; then
    pass "${label} no hits across ${blocks_scanned} code block(s)"
  else
    fail "${label} forbidden pattern present in references/examples:"
    while IFS= read -r line; do
      [[ -n "$line" ]] && printf '       %s\n' "$line"
    done <<< "$hits"
  fi
}

scan_pattern "HG-05 ext-URL (double-quoted)"        'src="https?:|href="https?:|@import url\(https?:'
scan_pattern "HG-06(a) JS network APIs"             '\bfetch\(|XMLHttpRequest|new[[:space:]]+WebSocket\(|new[[:space:]]+EventSource\(|navigator\.sendBeacon'
scan_pattern "HG-06(b) single-quoted ext-URL"       "src='https?:|href='https?:|@import url\('https?:"
scan_pattern "HG-06(c) CSS url(http) outside @import" 'url\([^)]*https?:'
scan_pattern "HG-06(d) ES module ext-import"        "import[[:space:]]+.+[[:space:]]+from[[:space:]]+[\"']https?:|import[(][[:space:]]*[\"']https?:"
scan_pattern "HG-06(e) external <iframe>/<embed>/<object>" "<iframe[^>]*src=[\"']https?:|<embed[^>]*src=[\"']https?:|<object[^>]*data=[\"']https?:"

# HG-06(c) special-case: scope this one to URL() only outside @import.
# We re-check separately because the generic pattern would over-match
# (@import url(http://...) is HG-05's responsibility).
# But the previous scan_pattern call already over-matches if @import url is
# present in a code block. Filter that out here as a post-check.
illegitimate_css_url="$(printf '%s\n' "$SCAN" | grep -E 'url\([^)]*https?:' | grep -vE '@import' || true)"
if [[ -n "$illegitimate_css_url" ]]; then
  # Already reported by scan_pattern above; this is just diagnostics.
  echo "    (HG-06(c) detail — URL refs outside @import:)"
  while IFS= read -r line; do
    [[ -n "$line" ]] && printf '       %s\n' "$line"
  done <<< "$illegitimate_css_url"
fi

# --- summary -----------------------------------------------------------------
echo "[lint-references] scanned ${blocks_scanned} code block(s) across ${#mds[@]} file(s); ${pass_count} ok, ${fail_count} fail"
if (( fail_count > 0 )); then
  exit 1
fi
exit 0
