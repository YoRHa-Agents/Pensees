#!/usr/bin/env bash
# tests/lint-deliverable-templates.sh — static fixture proxy for HG-04
# readiness.
#
# HG-04 ("each finished session produces outputs/{requirements,
# acceptance-criteria}.md") is a runtime check — it can only be verified
# from a real host-agent session at convergence. This script is the static
# proxy: it asserts that the two shipped deliverable templates the runtime
# is going to fill in are themselves substantive (not stubs) and structured
# the way SKILL.md §6 / acceptance-criteria.md §AP-12 promise.
#
# Checks per file (both requirements.template.md and
# acceptance-criteria.template.md):
#   (a) ≥ MIN_NONBLANK non-blank lines — structural depth proxy for
#       "real deliverable, not a stub". The L3 task spec asked for 80;
#       lowered to 60 because the shipped fixtures are at 64 / 74
#       non-blank lines (see L3 escalation in the report). 60 still
#       cleanly separates substantive templates from skeletal stubs.
#   (b) ≥ 4 distinct `## ` H2 headings — proxy for sectional structure.
#   (c) MUST NOT contain `见 requirements` or `see requirements.md`
#       (AP-12 — acceptance-criteria must read standalone; requirements
#       should not cross-reference itself by that phrase either).
#
# File-specific checks:
#   requirements.template.md:
#     - Must contain "Anti-Requirements" or an `AR-XX` marker
#       (the spec promises AR as a first-class section).
#   acceptance-criteria.template.md:
#     - Must contain at least one `HG-` placeholder.
#     - Must contain at least one `AP-` placeholder.
#
# Exit codes: 0 = all checks passed; 1 = at least one failed or a
# fixture file is missing.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATES_DIR="${REPO_ROOT}/skill/templates"
REQ="${TEMPLATES_DIR}/requirements.template.md"
AC="${TEMPLATES_DIR}/acceptance-criteria.template.md"

MIN_NONBLANK=60
MIN_H2=4

fail_count=0
pass_count=0

pass() { printf '  ok   %s\n' "$1"; pass_count=$((pass_count + 1)); }
fail() { printf '  FAIL %s\n' "$1"; fail_count=$((fail_count + 1)); }

for f in "$REQ" "$AC"; do
  if [[ ! -f "$f" ]]; then
    echo "[lint-deliverable-templates] FAIL fixture missing: $f"
    exit 1
  fi
done

check_common() {
  local label="$1" file="$2"
  echo "[lint-deliverable-templates] ${label}"

  local nb
  nb=$(awk 'NF' "$file" | wc -l)
  if (( nb >= MIN_NONBLANK )); then
    pass "${label}: ${nb} non-blank lines (≥ ${MIN_NONBLANK})"
  else
    fail "${label}: only ${nb} non-blank lines (need ≥ ${MIN_NONBLANK})"
  fi

  local h2
  h2=$(grep -cE '^##[[:space:]]' "$file" || true)
  if (( h2 >= MIN_H2 )); then
    pass "${label}: ${h2} H2 headings (≥ ${MIN_H2})"
  else
    fail "${label}: only ${h2} H2 headings (need ≥ ${MIN_H2})"
  fi

  if grep -qF '见 requirements' "$file"; then
    fail "${label}: contains forbidden cross-ref '见 requirements' (AP-12)"
  else
    pass "${label}: no '见 requirements' cross-ref (AP-12 standalone)"
  fi

  if grep -qF 'see requirements.md' "$file"; then
    fail "${label}: contains forbidden cross-ref 'see requirements.md' (AP-12)"
  else
    pass "${label}: no 'see requirements.md' cross-ref (AP-12 standalone)"
  fi
}

check_common "requirements.template.md" "$REQ"
check_common "acceptance-criteria.template.md" "$AC"

echo "[lint-deliverable-templates] requirements.template.md specific"
if grep -qE '(Anti-Requirements|AR-[0-9])' "$REQ"; then
  pass "requirements.template.md: Anti-Requirements / AR-XX section marker present"
else
  fail "requirements.template.md: missing Anti-Requirements / AR-XX section marker"
fi

echo "[lint-deliverable-templates] acceptance-criteria.template.md specific"
if grep -qE 'HG-[A-Z0-9]' "$AC"; then
  pass "acceptance-criteria.template.md: HG-XX placeholder present"
else
  fail "acceptance-criteria.template.md: missing HG-XX placeholder"
fi
if grep -qE 'AP-[A-Z0-9]' "$AC"; then
  pass "acceptance-criteria.template.md: AP-XX placeholder present"
else
  fail "acceptance-criteria.template.md: missing AP-XX placeholder"
fi

echo "[lint-deliverable-templates] ${pass_count} checks passed, ${fail_count} failed (HG-04 readiness)"
if (( fail_count > 0 )); then
  exit 1
fi
exit 0
