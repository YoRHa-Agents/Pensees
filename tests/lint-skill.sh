#!/usr/bin/env bash
# tests/lint-skill.sh — static lint for skill/SKILL.md and skill/**/*.md.
#
# Covers the static-verifiable subset of HG-08..HG-13 from
# .local/memory/specs/pensees/acceptance-criteria.md plus AR-06 / AR-10 /
# AP-08 / AP-09 from requirements.md.
#
# Exit codes: 0 = all checks passed; non-zero = at least one check failed.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL="${REPO_ROOT}/skill/SKILL.md"

fail_count=0
pass_count=0

pass() { printf '  ok   %s\n' "$1"; pass_count=$((pass_count + 1)); }
fail() { printf '  FAIL %s\n' "$1"; fail_count=$((fail_count + 1)); }

echo "[lint-skill] checking ${SKILL}"

# --- HG-09: SKILL.md body ≤ 300 lines -----------------------------------------
# Cap raised from 250 -> 300 in v0.3.2 to accommodate §14 Mid-result analysis
# (F-32..F-37) stub; the long-form prose for those rules lives in
# skill/references/mid-result-guardrails.md so the Tier-1 SKILL.md stays the
# concise runtime contract. Future bumps require an explicit design pass.
# v0.3.3 added F-38 structured-tool wiring (~16 lines); stays within 300.
if [[ ! -f "$SKILL" ]]; then
  fail "HG-09 SKILL.md missing at $SKILL"
else
  lines=$(wc -l < "$SKILL")
  if (( lines <= 300 )); then
    pass "HG-09 SKILL.md ≤ 300 lines (actual: ${lines})"
  else
    fail "HG-09 SKILL.md is ${lines} lines (limit 300)"
  fi
fi

# --- AR-06 / AP-05: description must not contain inducing phrases -------------
if grep -qiE "general planning|any thinking|always helpful|for all tasks" "$SKILL"; then
  fail "AR-06 frontmatter description contains an inducing phrase"
else
  pass "AR-06 frontmatter has no inducing phrases"
fi

# --- HG-08: HARD-GATE keyword present -----------------------------------------
if grep -q "HARD-GATE" "$SKILL"; then
  pass "HG-08 SKILL.md mentions HARD-GATE"
else
  fail "HG-08 SKILL.md missing HARD-GATE marker"
fi

# --- HG-11: emergency-stop phrases present ------------------------------------
hg11_hits=0
for phrase in "销毁本会话" "forget this" "wipe session"; do
  if grep -q -- "$phrase" "$SKILL"; then
    hg11_hits=$((hg11_hits + 1))
  fi
done
if (( hg11_hits == 3 )); then
  pass "HG-11 all 3 emergency-stop phrases present"
else
  fail "HG-11 only ${hg11_hits}/3 emergency-stop phrases present"
fi

# --- HG-12: local preview port markers (127.0.0.1 and 8765) -------------------
if grep -q "127.0.0.1" "$SKILL" && grep -q "8765" "$SKILL"; then
  pass "HG-12 SKILL.md mentions 127.0.0.1 and 8765"
else
  fail "HG-12 SKILL.md missing 127.0.0.1 or 8765"
fi

# --- HG-13: option-detail probe — (e) plus all 4 section names ---------------
if grep -qF "(e)" "$SKILL"; then
  e_ok=1
else
  e_ok=0
fi
miss=()
for section in "后果" "对比" "场景" "未知"; do
  if ! grep -q -- "$section" "$SKILL"; then
    miss+=("$section")
  fi
done
if (( e_ok == 1 )) && (( ${#miss[@]} == 0 )); then
  pass "HG-13 (e) and all 4 detail sections present (后果/对比/场景/未知)"
else
  fail "HG-13 missing — e_ok=${e_ok}, missing_sections=[${miss[*]:-none}]"
fi

# --- HG-14: structured-question tool wiring (F-38, v0.3.3) -------------------
hg14_missing=()
for marker in "F-38" "AskQuestion" "structured-question tool"; do
  if ! grep -qF -- "$marker" "$SKILL"; then
    hg14_missing+=("$marker")
  fi
done
if (( ${#hg14_missing[@]} == 0 )); then
  pass "HG-14 F-38 structured-question tool wiring documented in SKILL.md"
else
  fail "HG-14 SKILL.md missing F-38 markers: [${hg14_missing[*]}]"
fi

# --- AR-10 / AP-08: software vocab without gloss -------------------------------
# A "gloss" = a Chinese parenthetical or equivalent within the same sentence
# (~80 chars after the term). We scan the skill bundle (excluding the example
# session, which is allowed to use the vocab inside a worked transcript).
software_files=$(find "${REPO_ROOT}/skill" -name '*.md' -not -path '*/examples/*')
software_hits=0
while IFS= read -r f; do
  # Match standalone English software terms; require they be followed within
  # ~80 chars on the same line by a Chinese gloss (any Chinese character).
  # If a hit lacks a downstream Chinese character on the line, flag it.
  while IFS=: read -r ln content; do
    case "$content" in
      *endpoint*|*module*|*commit*|*deploy*|*" PR "*)
        # Skip lines that are inside a code block delimiter heuristic
        # (the gloss check is by-line, not block-aware — accept the false
        # positive risk and let reviewer decide).
        if ! printf '%s' "$content" | grep -qE '[\xe4-\xe9][\x80-\xbf][\x80-\xbf]'; then
          fail "AR-10 ${f##*/}:${ln}: software term without same-line gloss: ${content:0:120}"
          software_hits=$((software_hits + 1))
        fi
        ;;
    esac
  done < <(grep -nE "\bendpoint\b|\bmodule\b|\bcommit\b|\bdeploy\b| PR " "$f" || true)
done <<< "$software_files"
if (( software_hits == 0 )); then
  pass "AR-10 no ungllossed software-only vocab in skill/ (excluding examples/)"
fi

# --- AP-09: subjective-word presence outside example / AP citations / code fences ---
# Walk every skill/**/*.md; track:
#   - fenced-code-block state (skip lines inside ```...```);
#   - active AP paragraph (a paragraph that starts with `- **AP-XX**` continues
#     until the next blank line and counts as a citation, not a real use);
#   - lines that mention AP-09 / subjective-word / Forbidden in (definitions);
#   - lines where the subjective word itself is backticked (`更好` etc.) — that
#     is the citation form, not a real subjective claim.
ap09_hits=0
while IFS= read -r f; do
  case "$f" in
    */examples/*) continue ;;
  esac
  awk -v F="$f" '
    BEGIN { in_fence = 0; in_ap_para = 0 }
    /^```/ { in_fence = !in_fence; next }
    in_fence { next }
    # Detect start of an AP-XX bullet paragraph.
    /^[[:space:]]*[-*][[:space:]]+\*\*AP-/ { in_ap_para = 1; next }
    # Blank line terminates the AP paragraph.
    /^[[:space:]]*$/ { in_ap_para = 0; next }
    in_ap_para { next }
    # Inline citations / definition lines.
    /AP-09/ { next }
    /subjective-word/ { next }
    /Forbidden in/ { next }
    # If every subjective-word hit on this line is inside backticks, treat as citation.
    /should be good|更好|合理|优雅|挺好/ {
      line = $0
      # Strip all backtick-wrapped runs from the line, then re-check.
      stripped = line
      while (match(stripped, /`[^`]*`/)) {
        stripped = substr(stripped, 1, RSTART - 1) substr(stripped, RSTART + RLENGTH)
      }
      if (stripped ~ /should be good|更好|合理|优雅|挺好/) {
        printf("AP09:%s:%d:%s\n", F, NR, $0)
      }
    }
  ' "$f"
done < <(find "${REPO_ROOT}/skill" -name '*.md') > /tmp/ap09_hits.$$

if [[ -s /tmp/ap09_hits.$$ ]]; then
  while IFS= read -r line; do
    fail "AP-09 subjective word present: ${line#AP09:}"
    ap09_hits=$((ap09_hits + 1))
  done < /tmp/ap09_hits.$$
fi
rm -f /tmp/ap09_hits.$$
if (( ap09_hits == 0 )); then
  pass "AP-09 no subjective words outside examples / AP citations / code fences"
fi

# --- summary ------------------------------------------------------------------
echo "[lint-skill] ${pass_count} passed, ${fail_count} failed"
if (( fail_count > 0 )); then
  exit 1
fi
exit 0
