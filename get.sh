#!/bin/sh
# get.sh — Pensees curl-bootstrap installer.
#
# Canonical one-liner (user-facing):
#   curl -fsSL https://yorha-agents.github.io/Pensees/get.sh | sh
#
# Pass-through to install.sh after `--`:
#   curl -fsSL https://yorha-agents.github.io/Pensees/get.sh | sh -s -- --target=cursor
#
# Or directly:
#   sh get.sh [--target=cursor|--target=claude|--target=codex] [...other install.sh args]
#
# Environment (defaults shown):
#   PENSEES_HOME=$HOME/.local/share/pensees   install root
#   PENSEES_VERSION=latest                    release tag, "latest", or "main"
#   PENSEES_REPO=YoRHa-Agents/Pensees         GitHub org/repo
#   PENSEES_DOWNLOAD_URL_BASE=(unset)         host+path prefix for tarball downloads
#                                             (defaults to https://github.com/<repo>/archive)
#   PENSEES_API_URL_BASE=https://api.github.com   latest-release API host
#   PENSEES_NO_INSTALL=0                      if 1, skip the final ./install.sh call
#   PENSEES_VERBOSE=0                         if 1, `set -x` for debugging
#
# Exit codes (see design §6.4):
#   0   success (or idempotent skip)
#   1   generic / safety net
#   2   unrecognized argument
#   3   unsupported platform (native Windows etc.)
#   4   missing required tool (curl / tar / mkdir / mv / rm / uname)
#   5   GitHub release-API lookup failed (when resolving "latest")
#   6   tarball download failed or empty
#   7   tarball extract failed (corrupted or unexpected layout)
#   8   reserved
#   9   backup move failed (write permissions on PENSEES_HOME)
#   10+ install.sh's own exit code, forwarded verbatim
#
# Per AGENTS.md §2 every non-zero exit emits an `ERROR:` line and a `HINT:`
# line to stderr.  No silent fallbacks.
#
# POSIX `#!/bin/sh` — no bashisms.

set -u

# --- Env defaults -----------------------------------------------------------

PENSEES_HOME="${PENSEES_HOME:-$HOME/.local/share/pensees}"
PENSEES_VERSION="${PENSEES_VERSION:-latest}"
PENSEES_REPO="${PENSEES_REPO:-YoRHa-Agents/Pensees}"
PENSEES_DOWNLOAD_URL_BASE="${PENSEES_DOWNLOAD_URL_BASE:-}"
PENSEES_API_URL_BASE="${PENSEES_API_URL_BASE:-https://api.github.com}"
PENSEES_NO_INSTALL="${PENSEES_NO_INSTALL:-0}"
PENSEES_VERBOSE="${PENSEES_VERBOSE:-0}"

if [ "$PENSEES_VERBOSE" = "1" ]; then
  set -x
fi

# --- Error helpers ----------------------------------------------------------

# err <code> <error_message> <hint_message>
err() {
  printf 'ERROR: %s\n' "$2" >&2
  printf 'HINT: %s\n' "$3" >&2
  exit "$1"
}

# Cleanup of any temp dirs we create.
CLEANUP_DIRS=""
cleanup() {
  if [ -n "$CLEANUP_DIRS" ]; then
    # shellcheck disable=SC2086
    rm -rf $CLEANUP_DIRS 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM HUP

# --- Step 1: header ---------------------------------------------------------

echo "Pensees installer (curl-bootstrap)"

# --- Step 2: platform check -------------------------------------------------

UNAME_S=$(uname -s 2>/dev/null || echo "unknown")
case "$UNAME_S" in
  Darwin|Linux|FreeBSD)
    : # supported
    ;;
  MINGW*|MSYS*|CYGWIN*)
    err 3 \
      "unsupported platform: ${UNAME_S} (run inside WSL)" \
      "Install Windows Subsystem for Linux (WSL2) and re-run there. See https://learn.microsoft.com/windows/wsl/install."
    ;;
  *)
    err 3 \
      "unsupported platform: ${UNAME_S}" \
      "Pensees supports Darwin, Linux, and FreeBSD. File an issue if you believe this should work."
    ;;
esac

# --- Step 3: required tools -------------------------------------------------

for tool in curl tar mkdir mv rm uname; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    err 4 \
      "missing required tool: ${tool}" \
      "Install ${tool} on PATH and re-run.  Debian/Ubuntu: apt-get install -y ${tool}; macOS: tools ship with the system or via brew."
  fi
done

# --- Step 4: PENSEES_HOME ---------------------------------------------------

if ! mkdir -p "$PENSEES_HOME" 2>/dev/null; then
  err 1 \
    "could not create install root: $PENSEES_HOME" \
    "Check the value of PENSEES_HOME and the filesystem permissions of its parent."
fi
if [ ! -w "$PENSEES_HOME" ]; then
  err 1 \
    "install root is not writable: $PENSEES_HOME" \
    "Check filesystem permissions or pick a writable PENSEES_HOME."
fi

# --- Step 5: resolve version ------------------------------------------------

TAG=""
TARBALL_PATH=""
case "$PENSEES_VERSION" in
  latest)
    API_URL="$PENSEES_API_URL_BASE/repos/$PENSEES_REPO/releases/latest"
    echo "[resolve] querying latest release: $API_URL"
    API_BODY=""
    if ! API_BODY=$(curl -fsSL "$API_URL" 2>/dev/null); then
      err 5 \
        "GitHub release-API lookup failed: $API_URL" \
        "Network down or unauthenticated rate-limit (60/hr).  Pin PENSEES_VERSION=vX.Y.Z to bypass the API."
    fi
    TAG=$(printf '%s\n' "$API_BODY" \
          | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' \
          | head -n 1 \
          | sed 's/.*"\([^"]*\)"$/\1/')
    if [ -z "$TAG" ]; then
      err 5 \
        "could not parse tag_name from API response: $API_URL" \
        "API returned an unexpected payload.  Pin PENSEES_VERSION=vX.Y.Z to bypass the lookup."
    fi
    TARBALL_PATH="refs/tags/$TAG.tar.gz"
    ;;
  main)
    TAG="main"
    TARBALL_PATH="refs/heads/main.tar.gz"
    ;;
  *)
    TAG="$PENSEES_VERSION"
    TARBALL_PATH="refs/tags/$TAG.tar.gz"
    ;;
esac

# --- Step 6: compose download URL ------------------------------------------

if [ -n "$PENSEES_DOWNLOAD_URL_BASE" ]; then
  URL_BASE="$PENSEES_DOWNLOAD_URL_BASE"
else
  URL_BASE="https://github.com/$PENSEES_REPO/archive"
fi
TARBALL_URL="$URL_BASE/$TARBALL_PATH"

EXPECTED_DIR="$PENSEES_HOME/Pensees-$TAG"
CURRENT_LINK="$PENSEES_HOME/current"

# --- Step 9 (early): idempotency check -------------------------------------
#
# We do this BEFORE the download so a re-run with the same TAG is a cheap
# no-op (and does not hit the network at all).

if [ -L "$CURRENT_LINK" ]; then
  CURRENT_TARGET=$(readlink "$CURRENT_LINK" 2>/dev/null || true)
  if [ "$CURRENT_TARGET" = "Pensees-$TAG" ] \
     && [ -d "$EXPECTED_DIR" ] \
     && [ -f "$EXPECTED_DIR/skill/SKILL.md" ] \
     && grep -q '^name: pensees' "$EXPECTED_DIR/skill/SKILL.md" 2>/dev/null; then
    echo "[skip] already at $TAG"
    exit 0
  fi
fi

# --- Step 7: download tarball ----------------------------------------------

STAGING_DIR=$(mktemp -d 2>/dev/null) || \
  err 1 "mktemp -d failed for staging dir" "Check /tmp and TMPDIR permissions."
CLEANUP_DIRS="$CLEANUP_DIRS $STAGING_DIR"

TMP_TARBALL="$STAGING_DIR/pensees.tar.gz"
EXTRACT_DIR="$STAGING_DIR/extracted"
mkdir -p "$EXTRACT_DIR" || \
  err 1 "could not create extract dir: $EXTRACT_DIR" "Check /tmp permissions."

echo "[download] $TARBALL_URL"
DL_RC=0
curl -fsSL "$TARBALL_URL" -o "$TMP_TARBALL" || DL_RC=$?

ACTUAL_SIZE=0
if [ -f "$TMP_TARBALL" ]; then
  ACTUAL_SIZE=$(wc -c < "$TMP_TARBALL" 2>/dev/null | tr -d ' \t\n\r' || echo 0)
fi
ACTUAL_SIZE="${ACTUAL_SIZE:-0}"

if [ "$DL_RC" -ne 0 ]; then
  err 6 \
    "download failed: $TARBALL_URL (size=${ACTUAL_SIZE} bytes, curl rc=$DL_RC)" \
    "Confirm the tag/URL exists.  For a private mirror, set PENSEES_DOWNLOAD_URL_BASE."
fi

# Below 1024 bytes means we likely got an error page rather than a tarball.
if [ "$ACTUAL_SIZE" -lt 1024 ]; then
  err 6 \
    "download failed: $TARBALL_URL (size=${ACTUAL_SIZE} bytes, expected >= 1024)" \
    "Downloaded payload too small to be a valid release archive.  Verify PENSEES_VERSION and PENSEES_REPO."
fi

# --- Step 8: extract --------------------------------------------------------

echo "[extract] $TMP_TARBALL -> $EXTRACT_DIR"
if ! tar -xzf "$TMP_TARBALL" -C "$EXTRACT_DIR" 2>/dev/null; then
  err 7 \
    "tar extract failed for: $TMP_TARBALL (URL was $TARBALL_URL)" \
    "Tarball is corrupted or in an unexpected format.  Retry; file an issue if persistent."
fi

# Locate the extracted top-level directory.  GitHub archives are named
# Pensees-<tag>/ or Pensees-<branch>/.  We prefer the deterministic name,
# but fall back to the first directory we see.
EXTRACTED_DIR=""
if [ -d "$EXTRACT_DIR/Pensees-$TAG" ]; then
  EXTRACTED_DIR="$EXTRACT_DIR/Pensees-$TAG"
else
  for d in "$EXTRACT_DIR"/*/; do
    if [ -d "$d" ]; then
      EXTRACTED_DIR="${d%/}"
      break
    fi
  done
fi

if [ -z "$EXTRACTED_DIR" ] || [ ! -d "$EXTRACTED_DIR" ]; then
  err 7 \
    "extract produced no top-level directory in $EXTRACT_DIR" \
    "Tarball layout unexpected.  Expected Pensees-<TAG>/.  Verify PENSEES_REPO and PENSEES_VERSION."
fi
if [ ! -f "$EXTRACTED_DIR/skill/SKILL.md" ]; then
  err 7 \
    "extracted tree missing skill/SKILL.md: $EXTRACTED_DIR" \
    "Tarball does not look like a Pensees release.  Verify PENSEES_REPO and PENSEES_VERSION."
fi
if [ ! -f "$EXTRACTED_DIR/install.sh" ]; then
  err 7 \
    "extracted tree missing install.sh: $EXTRACTED_DIR" \
    "Tarball does not look like a Pensees release.  Verify PENSEES_REPO and PENSEES_VERSION."
fi

# --- Step 10: backup existing install --------------------------------------

if [ -L "$CURRENT_LINK" ] || [ -e "$CURRENT_LINK" ]; then
  CURRENT_FULL=""
  if [ -L "$CURRENT_LINK" ]; then
    CURRENT_TARGET=$(readlink "$CURRENT_LINK" 2>/dev/null || true)
    case "$CURRENT_TARGET" in
      /*) CURRENT_FULL="$CURRENT_TARGET" ;;
      ?*) CURRENT_FULL="$PENSEES_HOME/$CURRENT_TARGET" ;;
      *)  CURRENT_FULL="" ;;
    esac
  else
    CURRENT_FULL="$CURRENT_LINK"
  fi

  if [ -n "$CURRENT_FULL" ] && [ -d "$CURRENT_FULL" ] \
     && [ "$CURRENT_FULL" != "$EXPECTED_DIR" ]; then
    BACKUP_DIR="$PENSEES_HOME/.bak.$(date +%s 2>/dev/null || echo manual)"
    echo "[backup] $CURRENT_FULL -> $BACKUP_DIR/"
    if ! mkdir -p "$BACKUP_DIR" 2>/dev/null; then
      err 9 \
        "backup mkdir failed: $BACKUP_DIR" \
        "Check write permissions on $PENSEES_HOME."
    fi
    if ! mv "$CURRENT_FULL" "$BACKUP_DIR/" 2>/dev/null; then
      err 9 \
        "backup move failed: $CURRENT_FULL -> $BACKUP_DIR/" \
        "Check write permissions on $PENSEES_HOME and that no other process holds files in the old install."
    fi
  fi

  # Remove the stale 'current' symlink so the fresh ln -s below succeeds.
  if [ -L "$CURRENT_LINK" ]; then
    rm -f "$CURRENT_LINK" 2>/dev/null || \
      err 9 "could not remove stale symlink: $CURRENT_LINK" "Check permissions on $PENSEES_HOME."
  fi
fi

# --- Step 11: install: staging -> final ------------------------------------

if [ -e "$EXPECTED_DIR" ] && [ "$EXPECTED_DIR" != "$EXTRACTED_DIR" ]; then
  # Leftover from a partial install; remove it so the fresh `mv` succeeds.
  rm -rf "$EXPECTED_DIR" 2>/dev/null || \
    err 9 "could not remove stale target dir: $EXPECTED_DIR" "Check permissions on $PENSEES_HOME."
fi

echo "[install] $EXTRACTED_DIR -> $EXPECTED_DIR"
if ! mv "$EXTRACTED_DIR" "$EXPECTED_DIR" 2>/dev/null; then
  err 9 \
    "could not move staging into place: $EXTRACTED_DIR -> $EXPECTED_DIR" \
    "Check write permissions on $PENSEES_HOME."
fi

# Use a relative symlink so the install root can be moved as a unit.
( cd "$PENSEES_HOME" && rm -f current && ln -s "Pensees-$TAG" current ) || \
  err 9 \
    "could not create current symlink in $PENSEES_HOME" \
    "Check write permissions on $PENSEES_HOME."

# --- Step 12: invoke install.sh --------------------------------------------

if [ ! -f "$EXPECTED_DIR/install.sh" ]; then
  err 9 \
    "install.sh missing in extracted tree: $EXPECTED_DIR/install.sh" \
    "Tarball layout is wrong.  Re-fetch or verify PENSEES_REPO."
fi
if [ ! -x "$EXPECTED_DIR/install.sh" ]; then
  chmod +x "$EXPECTED_DIR/install.sh" 2>/dev/null || \
    err 9 "could not chmod +x install.sh: $EXPECTED_DIR/install.sh" "Check permissions."
fi

if [ "$PENSEES_NO_INSTALL" = "1" ]; then
  echo "[skip] PENSEES_NO_INSTALL=1 -- not invoking install.sh"
else
  echo "[install.sh] $EXPECTED_DIR/install.sh $*"
  INSTALL_RC=0
  ( cd "$EXPECTED_DIR" && ./install.sh "$@" ) || INSTALL_RC=$?
  if [ "$INSTALL_RC" -ne 0 ]; then
    printf 'ERROR: install.sh exited with code %s\n' "$INSTALL_RC" >&2
    printf 'HINT: see install.sh output above for the failure cause.\n' >&2
    exit "$INSTALL_RC"
  fi
fi

# --- Step 13: success summary -----------------------------------------------

echo "[done]"
echo "  installed: $EXPECTED_DIR"
echo "  symlink:   $CURRENT_LINK -> Pensees-$TAG"
echo "  verify:    ls \"\$HOME/.cursor/skills-cursor/pensees\""
echo "  next:      open Cursor / Claude Code / Codex CLI and try the phrase \"pensees, ...\""

exit 0
