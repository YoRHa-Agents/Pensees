#!/usr/bin/env bash
# tests/lint-transcript.sh — static fixture proxy for HG-07.
#
# HG-07 is fundamentally a runtime check ("each agent turn ends with at
# most one '?'") and can only be verified against a real host-agent session.
# This script is the static proxy: it asserts that the shipped teaching
# transcript at skill/examples/example-non-software-session.md itself does
# not contradict HG-07. If the example demonstrates HG-07 violations, the
# skill's own teaching material is unsafe, which is a meaningful static
# regression signal even though it is not a substitute for the real check.
#
# Parsing rules (matched to the file's actual format):
#   - Turn header lines start with `**` (case-sensitive). A header that
#     contains "User" or "Operator" ends the active agent turn; a header
#     that contains "Agent" or "Pensees" starts a new one. Other `**...**`
#     lines (e.g. "**(One day later)**") are scene breaks and ignored.
#   - Agent body lines are markdown block-quotes (`> ...`). After stripping
#     the `> ` prefix, the following lines are NOT counted as
#     sentence-ending questions:
#       * blank / whitespace-only;
#       * inside a fenced code block (```);
#       * starting with `ANN:` (reviewer annotation, not agent speech);
#       * starting with `(a)` .. `(f)` (multiple-choice option fragments);
#       * starting with whitespace (continuation of a bullet — questions
#         inside a list item are sub-prompts, not the turn's primary ask).
#   - For each remaining body line, a trailing `?` (after stripping
#     trailing whitespace) counts as one sentence-ending question.
#   - Pass: every agent turn has ≤ 1 counted `?`.
#
# Exit codes: 0 = all turns pass; 1 = at least one turn over the limit
# or fixture missing.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE="${REPO_ROOT}/skill/examples/example-non-software-session.md"

if [[ ! -f "$FIXTURE" ]]; then
  echo "[lint-transcript] FAIL fixture missing: $FIXTURE"
  exit 1
fi

echo "[lint-transcript] checking ${FIXTURE}"

awk '
function record_turn() {
  if (in_agent && agent_start > 0) {
    turns++
    if (q_count <= 1) {
      printf("  ok   agent turn @ line %d: %d sentence-end ? (within HG-07 limit)\n", agent_start, q_count)
      passed++
    } else {
      excerpt = substr(last_q_line, 1, 80)
      printf("  FAIL agent turn @ line %d: %d sentence-end ? (HG-07 violation). Last offending: %s\n", agent_start, q_count, excerpt)
      failed++
    }
  }
  in_agent = 0
  agent_start = 0
  q_count = 0
  last_q_line = ""
  in_fence = 0
}

BEGIN {
  in_agent = 0; agent_start = 0; q_count = 0
  last_q_line = ""; in_fence = 0
  turns = 0; passed = 0; failed = 0
}

/^\*\*/ {
  if ($0 ~ /User/ || $0 ~ /Operator/) {
    record_turn()
    next
  }
  if ($0 ~ /Agent/ || $0 ~ /Pensees/) {
    record_turn()
    in_agent = 1
    agent_start = NR
    next
  }
  next
}

!in_agent { next }

{
  body = $0
  sub(/^>[[:space:]]?/, "", body)

  if (substr(body, 1, 3) == "```") {
    in_fence = !in_fence
    next
  }
  if (in_fence) { next }

  if (body ~ /^ANN:/) { next }
  if (body ~ /^[[:space:]]*$/) { next }
  if (body ~ /^\([a-f]\)/) { next }
  if (body ~ /^[[:space:]]/) { next }

  sub(/[[:space:]]+$/, "", body)

  if (body ~ /\?$/) {
    q_count++
    last_q_line = body
  }
}

END {
  record_turn()
  printf("[lint-transcript] %d agent turns, %d passed, %d failed (HG-07 static fixture)\n", turns, passed, failed)
  exit(failed > 0 ? 1 : 0)
}
' "$FIXTURE"
