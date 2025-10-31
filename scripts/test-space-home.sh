#!/bin/sh
# Minimal harness to simulate a HOME with spaces and exercise keychain behaviors
# Usage: scripts/test-space-home.sh <version> [optional-extra-key]
# It creates a temp directory with a space, sets HOME, prepares dummy ssh keys,
# runs keychain, and reports whether pidfiles and ssh-add succeeded.
# Returns 0 on success, non-zero on failure.

set -eu
VER=${1:-test}
EXTRA_KEY=${2:-}
FAILED=0

WORKBASE=$(mktemp -d)
SPACE_HOME="${WORKBASE}/User Space"
mkdir -p "${SPACE_HOME}/.ssh" "${SPACE_HOME}/bin"
cp keychain.sh "${SPACE_HOME}/bin/keychain" 2>/dev/null || cp ./keychain.sh "${SPACE_HOME}/bin/keychain"
chmod 700 "${SPACE_HOME}/.ssh"

# Generate minimal throwaway key if ssh-keygen available
if command -v ssh-keygen >/dev/null 2>&1; then
  ssh-keygen -t ed25519 -N '' -f "${SPACE_HOME}/.ssh/id_ed25519" >/dev/null 2>&1 || true
fi

# Optional additional key copy
if [ -n "$EXTRA_KEY" ] && [ -f "$EXTRA_KEY" ]; then
  cp "$EXTRA_KEY" "${SPACE_HOME}/.ssh/" 2>/dev/null || true
fi

export HOME="${SPACE_HOME}"
export PATH="${SPACE_HOME}/bin:${PATH}"

printf '\n[info] Simulated HOME with space: %s\n' "$HOME"
printf '[info] Running keychain (version stub %s) ...\n' "$VER"

# Basic invocation: adopt or spawn then load one key
if output=$("${SPACE_HOME}/bin/keychain" -q --eval id_ed25519 2>&1); then
  echo "$output" | sed 's/^/[keychain] /'
else
  echo "$output" | sed 's/^/[keychain-err] /' >&2
  echo "ERROR: keychain command failed" >&2
  FAILED=1
fi

# Inspect pidfiles
PIDBASE="${HOME}/.keychain/$(uname -n 2>/dev/null || echo host)"
for suffix in -sh -csh -fish; do
  f="${PIDBASE}${suffix}"
  if [ -f "$f" ]; then
    echo "[pidfile] Found $f"; head -n 2 "$f" | sed 's/^/[pidfile] /'
  else
    echo "ERROR: pidfile MISSING: $f" >&2
    FAILED=1
  fi
done

# Verify that SSH_AUTH_SOCK has not been truncated
if eval "$(cat "${PIDBASE}-sh" 2>/dev/null || echo true)"; then
  case "$SSH_AUTH_SOCK" in
    *" "*)
      echo "ERROR: SSH_AUTH_SOCK contains a space unexpectedly: $SSH_AUTH_SOCK" >&2
      FAILED=1
      ;;
    *)
      if [ -S "$SSH_AUTH_SOCK" ]; then
        echo "[ok] SSH_AUTH_SOCK socket exists"
      else
        echo "ERROR: SSH_AUTH_SOCK path not a socket: $SSH_AUTH_SOCK" >&2
        FAILED=1
      fi
      ;;
  esac
else
  echo "ERROR: Unable to eval sh pidfile" >&2
  FAILED=1
fi

# Attempt ssh-add -l to confirm agent access
if ssh-add -l >/dev/null 2>&1; then
  echo "[ok] ssh-add -l succeeded"
else
  echo "ERROR: ssh-add -l failed" >&2
  FAILED=1
fi

# Cleanup summary (keep workspace for inspection) - comment out to retain
# rm -rf "$WORKBASE"

if [ $FAILED -eq 0 ]; then
  echo "[done] All tests PASSED"
  exit 0
else
  echo "[done] Tests FAILED - see errors above" >&2
  exit 1
fi
