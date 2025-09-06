#!/bin/sh
# Generate release notes body (ChangeLog excerpt + provenance table).
# Usage: release-notes.sh <version> <output-file>
# Respects KEYCHAIN_ASSET_* path variables if set (for CI artifact selection).
set -eu
VER=${1:?usage: release-notes.sh <version> <output-file>}
OUT=${2:?usage: release-notes.sh <version> <output-file>}

[ -f ChangeLog.md ] || { echo "ChangeLog.md not found" >&2; exit 1; }
[ "$(cat VERSION)" = "$VER" ] || { echo "VERSION mismatch ($(cat VERSION) != $VER)" >&2; exit 1; }

awk -v ver="$VER" '/^## keychain '"$VER"' /{f=1;print;next} /^## keychain / && f && $0 !~ ver {exit} f' ChangeLog.md > "$OUT"
[ -s "$OUT" ] || { echo "Failed to extract section for $VER" >&2; exit 1; }

ASSET_KEYCHAIN=${KEYCHAIN_ASSET_KEYCHAIN:-keychain}
ASSET_MAN=${KEYCHAIN_ASSET_MAN:-keychain.1}

if [ -f "$ASSET_KEYCHAIN" ] && [ -f "$ASSET_MAN" ]; then
  k_sha256=$(sha256sum "$ASSET_KEYCHAIN" | awk '{print $1}')
  man_sha256=$(sha256sum "$ASSET_MAN" | awk '{print $1}')
  commit_sha1=$(git rev-list -n1 "$VER" 2>/dev/null || true)
  {
    echo
    echo '---'
    echo
    echo '### Build Provenance'
    echo
    echo '| Artifact | SHA256 |'
    echo '|----------|--------|'
    echo "| keychain | $k_sha256 |"
    echo "| keychain.1 | $man_sha256 |"
    echo
    echo "Tag commit SHA1: \`$commit_sha1\`"
  } >> "$OUT"
fi

exit 0
