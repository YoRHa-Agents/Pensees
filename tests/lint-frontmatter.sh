#!/usr/bin/env bash
# tests/lint-frontmatter.sh — static lint for skill/SKILL.md YAML frontmatter.
#
# Covers the STATIC-VERIFIABLE preconditions of HG-01 / HG-02 / HG-03
# (Cursor / Claude Code / Codex CLI all autoload the skill on a trigger
# phrase). If the YAML frontmatter is malformed, missing required fields,
# or has a description that omits the trigger phrases, NO host agent will
# autoload regardless of how good the install is. Catching that statically
# is the necessary-but-not-sufficient half of HG-01..HG-03; the runtime
# autoload smoke in a real Cursor / Claude Code / Codex CLI session remains
# the source of truth and is documented as such in tests/run.sh.
#
# Checks:
#   FM-1  Frontmatter exists (lines 1 + N both `---`, N > 1).
#   FM-2  Parses as valid YAML (python3 -c "import yaml; yaml.safe_load(...)")
#         OR — if PyYAML is missing — at least passes a structural awk parse.
#   FM-3  Required key `name:` exists and equals "pensees".
#   FM-4  Required key `description:` exists and is non-empty.
#   FM-5  Description length ≤ 1024 chars (Si-Chip §24.1 BLOCKER 15 alignment).
#   FM-6  Description contains at least one trigger phrase from each language
#         family Pensees claims to support (zh + en).
#   FM-7  Description does NOT contain an autoload-inducing phrase
#         (mirrors lint-skill.sh AR-06 / AP-05 — we re-check here so the
#          frontmatter contract is self-contained).
#
# Exit codes: 0 = all checks passed; 1 = at least one failed.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL="${REPO_ROOT}/skill/SKILL.md"

fail_count=0
pass_count=0

pass() { printf '  ok   %s\n' "$1"; pass_count=$((pass_count + 1)); }
fail() { printf '  FAIL %s\n' "$1"; fail_count=$((fail_count + 1)); }

echo "[lint-frontmatter] checking ${SKILL}"

if [[ ! -f "$SKILL" ]]; then
  echo "[lint-frontmatter] FAIL SKILL.md missing at $SKILL"
  exit 1
fi

# --- FM-1: frontmatter delimiters --------------------------------------------
first_line="$(head -n 1 "$SKILL")"
if [[ "$first_line" != "---" ]]; then
  fail "FM-1 line 1 is not '---' (got: '${first_line}')"
else
  # Find the SECOND `---` on its own line.
  second_dash_line=$(awk 'NR==1 && /^---$/ {next} /^---$/ {print NR; exit}' "$SKILL")
  if [[ -z "$second_dash_line" ]]; then
    fail "FM-1 no closing '---' found"
  elif (( second_dash_line < 3 )); then
    fail "FM-1 closing '---' too close to opener (line ${second_dash_line})"
  else
    pass "FM-1 frontmatter delimited (lines 1..${second_dash_line})"
    FRONTMATTER_END=$second_dash_line
  fi
fi

if (( fail_count > 0 )); then
  echo "[lint-frontmatter] aborting after FM-1 failure"
  exit 1
fi

# Extract the YAML body (lines 2 .. FRONTMATTER_END-1) into a temp file.
TMP_YAML="$(mktemp -t pensees-fm-XXXX.yaml)"
trap 'rm -f "$TMP_YAML"' EXIT
awk -v end="$FRONTMATTER_END" 'NR > 1 && NR < end' "$SKILL" > "$TMP_YAML"

# --- FM-2: parses as valid YAML ----------------------------------------------
# Prefer python3 + PyYAML; fall back to a structural-awk check if PyYAML is
# unavailable. NO silent fallback: if neither path works, we FAIL the lint.
parse_ok=0
parse_method="(unknown)"
if command -v python3 >/dev/null 2>&1; then
  if python3 -c '
import sys, yaml
try:
    d = yaml.safe_load(open(sys.argv[1]))
    if not isinstance(d, dict):
        sys.exit("FM-2: frontmatter did not parse as a YAML mapping")
    sys.exit(0)
except yaml.YAMLError as e:
    sys.exit(f"FM-2: YAML parse error: {e}")
' "$TMP_YAML" 2>/dev/null; then
    parse_ok=1
    parse_method="python3 + PyYAML"
  fi
fi

if (( parse_ok == 0 )); then
  # Structural fallback: every non-blank, non-continuation line must look
  # like `key: value` (where continuation lines start with whitespace or `|`).
  if awk '
    BEGIN { ok = 1 }
    /^[[:space:]]*$/ { next }
    /^[[:space:]]/   { next }   # continuation
    /^[|>]/          { next }   # block-scalar indicator
    /^[A-Za-z_][A-Za-z0-9_-]*:[[:space:]]*([|>]|.*)$/ { next }
    { printf("FM-2 structural-parse rejected line %d: %s\n", NR, $0) > "/dev/stderr"; ok = 0 }
    END { exit (ok ? 0 : 1) }
  ' "$TMP_YAML" 2>/dev/null; then
    parse_ok=1
    parse_method="awk structural parser (PyYAML missing — non-silent fallback)"
  fi
fi

if (( parse_ok == 1 )); then
  pass "FM-2 frontmatter parses as YAML (${parse_method})"
else
  fail "FM-2 frontmatter does not parse as YAML and no fallback succeeded"
fi

# --- FM-3: name == "pensees" -------------------------------------------------
name_value="$(awk -F: '/^name:[[:space:]]/ { sub(/^[[:space:]]+/, "", $2); print $2; exit }' "$TMP_YAML")"
if [[ "$name_value" == "pensees" ]]; then
  pass "FM-3 name: pensees"
else
  fail "FM-3 expected name: pensees, got: '${name_value}'"
fi

# --- FM-4: description exists, non-empty -------------------------------------
# Captures both `description: <inline>` and `description: |\n  multi\n  line`.
desc_body="$(awk '
  /^description:/ {
    inline = $0; sub(/^description:[[:space:]]*/, "", inline)
    if (inline == "|" || inline == ">" || inline == "|-" || inline == ">-") {
      block = 1; next
    }
    if (length(inline) > 0) { print inline; exit }
    block = 1; next
  }
  block && /^[^[:space:]]/ { exit }
  block && /^[[:space:]]/ { sub(/^[[:space:]]+/, ""); print }
' "$TMP_YAML" | tr -d '\n')"

desc_chars=${#desc_body}

if (( desc_chars == 0 )); then
  fail "FM-4 description is missing or empty"
else
  pass "FM-4 description present (${desc_chars} chars)"
fi

# --- FM-5: description ≤ 1024 chars ------------------------------------------
if (( desc_chars <= 1024 )); then
  pass "FM-5 description ≤ 1024 chars (actual: ${desc_chars})"
else
  fail "FM-5 description is ${desc_chars} chars (limit 1024 — Si-Chip §24.1 BLOCKER 15)"
fi

# --- FM-6: trigger phrases present in both zh and en -------------------------
zh_triggers=("pensees" "帮我想清楚" "理一下需求" "做需求澄清" "模糊的想法")
en_triggers=("pensees" "fuzzy thought" "help me think through" "clarify requirements" "elicit")

zh_hits=0
for t in "${zh_triggers[@]}"; do
  if [[ "$desc_body" == *"$t"* ]]; then
    zh_hits=$((zh_hits + 1))
  fi
done

en_hits=0
for t in "${en_triggers[@]}"; do
  if [[ "$desc_body" == *"$t"* ]]; then
    en_hits=$((en_hits + 1))
  fi
done

if (( zh_hits >= 2 )); then
  pass "FM-6 ≥ 2 zh trigger phrases present (${zh_hits}/${#zh_triggers[@]})"
else
  fail "FM-6 only ${zh_hits} zh trigger phrases present (need ≥ 2)"
fi

if (( en_hits >= 2 )); then
  pass "FM-6 ≥ 2 en trigger phrases present (${en_hits}/${#en_triggers[@]})"
else
  fail "FM-6 only ${en_hits} en trigger phrases present (need ≥ 2)"
fi

# --- FM-7: no autoload-inducing phrases --------------------------------------
# Pattern intentionally mirrors tests/lint-skill.sh AR-06 / AP-05 (single
# source of truth). Notably "autoload" is NOT in the pattern: the description
# legitimately says "Do NOT autoload for routine planning" — that is the
# enforced contract, not a violation. Catching "Do NOT autoload" as inducing
# would be a false positive (lint-skill.sh has the same allow-list).
inducing_pattern='general planning|any thinking task|always helpful|for all tasks'
inducing_hits="$(printf '%s' "$desc_body" | grep -ciE "$inducing_pattern" || true)"
if (( inducing_hits == 0 )); then
  pass "FM-7 no autoload-inducing phrases (AR-06 / AP-05 — mirrors lint-skill.sh allow-list)"
else
  fail "FM-7 description contains ${inducing_hits} inducing phrase hit(s) — AR-06 violated"
fi

# --- summary -----------------------------------------------------------------
echo "[lint-frontmatter] ${pass_count} passed, ${fail_count} failed"
if (( fail_count > 0 )); then
  exit 1
fi
exit 0
