#!/usr/bin/env bash
# install.sh — install / uninstall the Pensees skill into one or more
# agent skill directories.
#
# Targets (default = all three):
#   - Cursor       : ~/.cursor/skills-cursor/pensees
#   - Claude Code  : ~/.claude/skills/pensees
#   - Codex CLI    : ~/.codex/skills/pensees
#
# Usage:
#   ./install.sh                       # symlink to all 3 default target dirs under $HOME
#   ./install.sh --workspace PATH      # symlink to all 3 target dirs under PATH
#   ./install.sh --target=cursor       # single target (cursor|claude|codex)
#   ./install.sh --target cursor       # equivalent (space-separated)
#   ./install.sh --copy                # copy instead of symlink
#   ./install.sh --uninstall           # remove the 3 links/copies (safety-checked)
#   ./install.sh --dry-run             # print plan, do nothing
#   ./install.sh --help
#
# Errors loudly when the source ./skill/ directory is missing — no silent
# fallback (AGENTS.md §2 "No silent failures").
#
# The script is idempotent: re-running default install on top of an existing
# valid symlink is a no-op.

set -euo pipefail

# --- Resolve script-relative source path -------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${SCRIPT_DIR}/skill"

# --- Default state ----------------------------------------------------------

MODE="install"          # install | uninstall | dry-run
COPY=0                  # 0 = symlink, 1 = copy
ROOT_OVERRIDE=""        # if set, replaces $HOME as the install root for all 3 targets
SINGLE_TARGET=""        # cursor | claude | codex | "" (= all 3)

usage() {
  # Print only the leading comment block (everything up to the first blank
  # line followed by a non-comment line). Keeps --help in lockstep with the
  # header above without manual line-range tracking.
  awk '
    NR == 1 { next }                    # skip the shebang
    /^[^#]/ { exit }                    # stop at first non-comment line
    { sub(/^# ?/, ""); print }
  ' "${BASH_SOURCE[0]}"
}

# --- Parse args -------------------------------------------------------------

while (( "$#" )); do
  case "$1" in
    --workspace)
      shift
      if [[ $# -eq 0 || "$1" == --* ]]; then
        echo "ERROR: --workspace requires a PATH argument." >&2
        exit 2
      fi
      ROOT_OVERRIDE="$1"
      shift
      ;;
    --workspace=*)
      ROOT_OVERRIDE="${1#--workspace=}"
      shift
      ;;
    --target)
      shift
      if [[ $# -eq 0 || "$1" == --* ]]; then
        echo "ERROR: --target requires a name (cursor|claude|codex)." >&2
        exit 2
      fi
      SINGLE_TARGET="$1"
      shift
      ;;
    --target=*)
      SINGLE_TARGET="${1#--target=}"
      shift
      ;;
    --copy)
      COPY=1
      shift
      ;;
    --uninstall)
      MODE="uninstall"
      shift
      ;;
    --dry-run)
      MODE="dry-run"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

# --- Validate -----------------------------------------------------------------

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "ERROR: source skill/ directory not found at: $SOURCE_DIR" >&2
  echo "       Make sure you run install.sh from the Pensees repo root." >&2
  exit 1
fi
if [[ ! -r "$SOURCE_DIR/SKILL.md" ]]; then
  echo "ERROR: $SOURCE_DIR/SKILL.md missing or unreadable." >&2
  exit 1
fi

case "$SINGLE_TARGET" in
  ""|cursor|claude|codex) : ;;
  *)
    echo "ERROR: --target must be one of: cursor, claude, codex (got: $SINGLE_TARGET)" >&2
    exit 2
    ;;
esac

# --- Build target list ------------------------------------------------------

ROOT="${ROOT_OVERRIDE:-$HOME}"

# `target_paths[<key>]=<absolute path>` — bash 3 compatible via two parallel arrays.
TARGET_KEYS=(cursor claude codex)
TARGET_PATHS=(
  "${ROOT}/.cursor/skills-cursor/pensees"
  "${ROOT}/.claude/skills/pensees"
  "${ROOT}/.codex/skills/pensees"
)

selected_indices=()
if [[ -n "$SINGLE_TARGET" ]]; then
  for i in "${!TARGET_KEYS[@]}"; do
    if [[ "${TARGET_KEYS[$i]}" == "$SINGLE_TARGET" ]]; then
      selected_indices+=("$i")
    fi
  done
else
  selected_indices=(0 1 2)
fi

# --- Helpers ----------------------------------------------------------------

plan() {
  echo "[plan] $*"
}

do_install_one() {
  local key="$1"
  local dest="$2"
  local parent
  parent="$(dirname "$dest")"

  if [[ "$MODE" == "dry-run" ]]; then
    plan "ensure parent dir: $parent"
    if (( COPY )); then
      plan "copy $SOURCE_DIR  ->  $dest"
    else
      plan "symlink $SOURCE_DIR  ->  $dest"
    fi
    return 0
  fi

  mkdir -p "$parent"

  # Idempotency: if dest is already a symlink pointing at our source, skip.
  if (( COPY == 0 )) && [[ -L "$dest" ]]; then
    local current
    current="$(readlink "$dest")"
    if [[ "$current" == "$SOURCE_DIR" ]]; then
      echo "[skip] $key already linked: $dest -> $current"
      return 0
    fi
    echo "[relink] $key: $dest (was -> $current)"
    rm "$dest"
  elif [[ -e "$dest" || -L "$dest" ]]; then
    # Existing non-symlink path: refuse to clobber unless --copy explicitly chosen,
    # in which case we replace with a fresh copy.
    if (( COPY )); then
      echo "[replace-copy] $key: removing existing $dest before copy"
      rm -rf "$dest"
    else
      echo "ERROR: $dest already exists and is not a Pensees symlink." >&2
      echo "       Run with --copy to overwrite, or remove it manually first." >&2
      return 3
    fi
  fi

  if (( COPY )); then
    cp -R "$SOURCE_DIR" "$dest"
    echo "[copy] $key: $dest"
  else
    ln -s "$SOURCE_DIR" "$dest"
    echo "[link] $key: $dest -> $SOURCE_DIR"
  fi
}

do_uninstall_one() {
  local key="$1"
  local dest="$2"

  if [[ "$MODE" == "dry-run" ]]; then
    plan "uninstall: $key at $dest (if it is our symlink or a copy)"
    return 0
  fi

  if [[ ! -e "$dest" && ! -L "$dest" ]]; then
    echo "[skip] $key: nothing at $dest"
    return 0
  fi

  if [[ -L "$dest" ]]; then
    local current
    current="$(readlink "$dest")"
    if [[ "$current" == "$SOURCE_DIR" ]]; then
      rm "$dest"
      echo "[unlink] $key: removed symlink $dest"
      return 0
    fi
    echo "ERROR: $dest is a symlink but does not point to our skill source ($current)." >&2
    echo "       Refusing to delete unrelated install. Remove it manually if intended." >&2
    return 4
  fi

  # Directory case: only remove if it looks like a Pensees install (contains SKILL.md
  # that matches ours by frontmatter `name: pensees`). This protects unrelated dirs.
  if [[ -d "$dest" && -f "$dest/SKILL.md" ]] && \
     grep -q '^name: pensees' "$dest/SKILL.md" 2>/dev/null; then
    rm -rf "$dest"
    echo "[remove] $key: removed copy directory $dest"
    return 0
  fi

  echo "ERROR: $dest exists but does not look like a Pensees install (no matching SKILL.md)." >&2
  echo "       Refusing to delete. Inspect manually." >&2
  return 5
}

# --- Run --------------------------------------------------------------------

echo "Pensees install.sh"
echo "  source : $SOURCE_DIR"
echo "  mode   : $MODE"
echo "  copy   : $COPY"
echo "  root   : $ROOT"
if [[ -n "$SINGLE_TARGET" ]]; then
  echo "  target : $SINGLE_TARGET (single)"
else
  echo "  target : all (cursor, claude, codex)"
fi

rc=0
for i in "${selected_indices[@]}"; do
  key="${TARGET_KEYS[$i]}"
  path="${TARGET_PATHS[$i]}"
  if [[ "$MODE" == "uninstall" ]]; then
    do_uninstall_one "$key" "$path" || rc=$?
  else
    do_install_one "$key" "$path" || rc=$?
  fi
done

if (( rc != 0 )); then
  echo "FAILED with exit code $rc" >&2
  exit "$rc"
fi

if [[ "$MODE" == "dry-run" ]]; then
  echo "Dry-run complete. No changes made."
else
  echo "Done."
fi
