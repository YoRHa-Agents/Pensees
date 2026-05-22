#!/usr/bin/env bash
# tests/lint-repo-safety.sh — verify the .gitignore safety contract.
#
# Two-sided regression guard for the v0.3.1 repo safety patch
# (.local/memory/specs/pensees ledger + plan
#  .cursor/plans/v0.3.1_repo_safety_*.plan.md):
#
#   1. RS-IGNORE  paths that MUST be ignored — generated agent / IDE
#                 outputs, per-tool version pins, machine-local secret
#                 shapes, and previously-noisy entries surfaced in
#                 `git status` before this patch landed.
#   2. RS-TRACK   paths that MUST NOT be ignored — the source-of-truth
#                 surfaces the project ships (skill bundle, public site,
#                 docs, tests, governance rules, GitHub workflows, root
#                 readme / license / installer / installer test fixtures).
#
# Each check uses `git check-ignore -q -- <path>`; exit 0 = ignored,
# exit 1 = NOT ignored, exit >1 = git error (treated as FAIL). We do
# NOT require the path to exist on disk — `git check-ignore` matches
# against `.gitignore` rules string-wise, which is exactly the contract
# we want to lock down.
#
# Exit codes: 0 = all checks passed; 1 = at least one check failed.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

fail_count=0
pass_count=0

pass() { printf '  ok   %s\n' "$1"; pass_count=$((pass_count + 1)); }
fail() { printf '  FAIL %s\n' "$1"; fail_count=$((fail_count + 1)); }

echo "[lint-repo-safety] checking .gitignore contract from ${REPO_ROOT}"

# --- helpers ----------------------------------------------------------------

# expect_ignored <path> <label>
# PASS if `git check-ignore` reports the path as ignored (exit 0).
expect_ignored() {
  local path="$1"
  local label="$2"
  local rc
  git check-ignore -q -- "$path"
  rc=$?
  case "$rc" in
    0) pass "RS-IGNORE ${label}: '${path}' is ignored" ;;
    1) fail "RS-IGNORE ${label}: '${path}' is NOT ignored (expected ignored)" ;;
    *) fail "RS-IGNORE ${label}: 'git check-ignore' errored on '${path}' (rc=${rc})" ;;
  esac
}

# expect_tracked <path> <label>
# PASS if `git check-ignore` reports the path as NOT ignored (exit 1).
# We additionally require the path to exist on disk so the contract is
# anchored to a real source-of-truth surface — a phantom path passing
# this check would be a false positive.
expect_tracked() {
  local path="$1"
  local label="$2"
  if [[ ! -e "$path" ]]; then
    fail "RS-TRACK ${label}: '${path}' is missing from disk (cannot anchor contract)"
    return
  fi
  local rc
  git check-ignore -q -- "$path"
  rc=$?
  case "$rc" in
    0) fail "RS-TRACK ${label}: '${path}' IS ignored (expected tracked)" ;;
    1) pass "RS-TRACK ${label}: '${path}' is tracked" ;;
    *) fail "RS-TRACK ${label}: 'git check-ignore' errored on '${path}' (rc=${rc})" ;;
  esac
}

# --- RS-IGNORE: agent / IDE tooling state -----------------------------------
# Mirror of the directories observed in `git status` on a freshly
# tooled-up workstation before the patch (see the plan §Context).
expect_ignored ".local/anything"                            "I-01 agent workspace"
expect_ignored ".local/memory/specs/pensees/requirements.md" "I-02 nested local file"
expect_ignored ".agent/foo"                                 "I-03 .agent"
expect_ignored ".agent-worker-logs/foo.log"                 "I-04 .agent-worker-logs"
expect_ignored ".claude/skills/x.md"                        "I-05 .claude"
expect_ignored ".clinerules/devola-flow.md"                 "I-06 .clinerules"
expect_ignored ".codebuddy/skills/x.json"                   "I-07 .codebuddy"
expect_ignored ".codex/skills/x.md"                         "I-08 .codex"
expect_ignored ".continue/skills/x.md"                      "I-09 .continue"
expect_ignored ".cursor/plans/some.plan.md"                 "I-10 .cursor/plans (legacy)"
expect_ignored ".cursor/rules/repo-governance.mdc"          "I-11 .cursor/rules (legacy)"
expect_ignored ".cursor/skills-cursor/x.md"                 "I-12 .cursor (any subdir)"
expect_ignored ".gemini/x"                                  "I-13 .gemini"
expect_ignored ".kiro/x"                                    "I-14 .kiro"
expect_ignored ".opencode/x"                                "I-15 .opencode"
expect_ignored ".qoder/x"                                   "I-16 .qoder"
expect_ignored ".roo/rules/x.md"                            "I-17 .roo"
expect_ignored ".trae/x"                                    "I-18 .trae"
expect_ignored ".windsurf/x"                                "I-19 .windsurf"

# --- RS-IGNORE: per-tool version pins / single-file rule bundles ------------
expect_ignored ".devola-flow-version"                       "I-20 devola-flow version pin"
expect_ignored ".popola-loom-version"                       "I-21 popola-loom version pin"
expect_ignored ".windsurfrules"                             "I-22 .windsurfrules bundle"

# --- RS-IGNORE: GitHub-side agent helpers (workflows themselves stay tracked)
expect_ignored ".github/.popola-loom-version"               "I-23 github helper version pin"
expect_ignored ".github/copilot-instructions.md"            "I-24 github copilot helper"
expect_ignored ".github/prompts/foo.md"                     "I-25 github prompts dir"

# --- RS-IGNORE: DevolaFlow compiled outputs ---------------------------------
expect_ignored "AGENTS.md"                                  "I-26 AGENTS.md (root only)"
expect_ignored ".rules/.compile-hashes.json"                "I-27 compile cache"

# --- RS-IGNORE: secret / credential shapes ----------------------------------
expect_ignored ".env"                                       "I-30 .env"
expect_ignored ".env.local"                                 "I-31 .env.local"
expect_ignored ".env.production"                            "I-32 .env.<environment>"
expect_ignored ".env.staging.local"                         "I-33 .env.<env>.local"
expect_ignored "config/private.pem"                         "I-34 *.pem anywhere"
expect_ignored "secrets/api.key"                            "I-35 *.key anywhere"
expect_ignored "ssl/cert.crt"                               "I-36 *.crt anywhere"
expect_ignored "id_rsa"                                     "I-37 SSH private key"
expect_ignored "id_ed25519.pub.bak"                         "I-38 SSH key variant"
expect_ignored "credentials.json"                           "I-39 generic creds JSON"
expect_ignored "service-account-prod.json"                  "I-40 cloud service account"
expect_ignored "secrets.yaml"                               "I-41 secrets yaml"
expect_ignored ".secrets/db.txt"                            "I-42 .secrets dir"
expect_ignored ".local-secrets/anything"                    "I-43 .local-secrets dir"
expect_ignored ".direnv/python-3.11"                        "I-44 direnv cache"

# --- RS-IGNORE: language / build noise (smoke check existing block) --------
expect_ignored "node_modules/foo/index.js"                  "I-50 node_modules"
expect_ignored "src/__pycache__/x.pyc"                      "I-51 python cache"
expect_ignored "dist/bundle.js"                             "I-52 dist artifact"
expect_ignored "build/output.txt"                           "I-53 build artifact"
expect_ignored ".DS_Store"                                  "I-54 macOS metadata"
expect_ignored "logs/server.log"                            "I-55 logs dir"
expect_ignored "trace.log"                                  "I-56 *.log file"

# --- RS-TRACK: project source-of-truth surfaces -----------------------------
# Each path must exist on disk; expect_tracked enforces that.
expect_tracked "README.md"                                  "T-01 README"
expect_tracked "LICENSE"                                    "T-02 license"
expect_tracked ".gitignore"                                 "T-03 gitignore itself"
expect_tracked ".rules/soul.mdc"                            "T-04 soul rule"
expect_tracked ".rules/compile-config.yaml"                 "T-05 compile config"
expect_tracked ".github/workflows/test.yml"                 "T-06 test workflow"
expect_tracked ".github/workflows/pages.yml"                "T-07 pages workflow"
expect_tracked "skill/SKILL.md"                             "T-08 skill entry"
expect_tracked "docs/QUICK_GUIDE.md"                        "T-09 docs quick (en)"
expect_tracked "docs/QUICK_GUIDE.zh.md"                     "T-10 docs quick (zh)"
expect_tracked "docs/USER_GUIDE.md"                         "T-11 docs user (en)"
expect_tracked "docs/USER_GUIDE.zh.md"                      "T-12 docs user (zh)"
expect_tracked "site/index.html"                            "T-13 site landing"
expect_tracked "site/demo.html"                             "T-14 site demo"
expect_tracked "site/styles.css"                            "T-15 site styles"
expect_tracked "site/i18n.js"                               "T-16 site i18n"
expect_tracked "site/theme.js"                              "T-17 site theme"
expect_tracked "site/embedded-demos/01-preset-voice-comparison.html" \
                                                            "T-18 embedded demo"
expect_tracked "tests/run.sh"                               "T-19 gate runner"
expect_tracked "tests/lint-skill.sh"                        "T-20 existing lint"
expect_tracked "tests/lint-site.sh"                         "T-21 site lint"
expect_tracked "tests/smoke-install.sh"                     "T-22 install smoke"
expect_tracked "install.sh"                                 "T-23 installer"
expect_tracked "get.sh"                                     "T-24 curl bootstrap"

# --- summary ----------------------------------------------------------------
echo "[lint-repo-safety] ${pass_count} passed, ${fail_count} failed"
if (( fail_count > 0 )); then
  exit 1
fi
exit 0
