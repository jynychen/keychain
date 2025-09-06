#!/bin/sh
# Refresh (update) assets of an existing release. If the release does not exist, fail.
set -eu
VER=${1:?usage: release-refresh.sh <version>}
GITHUB_REPOSITORY=${GITHUB_REPOSITORY:-danielrobbins/keychain}
. "$(dirname "$0")/release-common.sh"

[ "$(cat VERSION)" = "$VER" ] || fail "VERSION file mismatch ($(cat VERSION)" != "$VER)"

rel_json=$(curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" https://api.github.com/repos/${GITHUB_REPOSITORY}/releases/tags/$VER || true)
[ -n "$rel_json" ] || fail "Release for tag $VER not found"
rel_id=$(printf '%s' "$rel_json" | jq '.id')
[ "$rel_id" != "null" ] || fail "Could not determine release id"

echo "Deleting existing assets..."
printf '%s' "$rel_json" | jq -r '.assets[].id' | while read -r aid; do
  [ -n "$aid" ] || continue
  curl -fsSL -X DELETE -H "Authorization: Bearer $GITHUB_TOKEN" https://api.github.com/repos/${GITHUB_REPOSITORY}/releases/assets/$aid >/dev/null || fail "Failed to delete asset $aid"
  echo " deleted asset id $aid"
done

echo "Uploading replacement assets..."
ASSET_KEYCHAIN=${KEYCHAIN_ASSET_KEYCHAIN:-keychain}
ASSET_MAN=${KEYCHAIN_ASSET_MAN:-keychain.1}
ASSET_TARBALL=${KEYCHAIN_ASSET_TARBALL:-keychain-$VER.tar.gz}

# (Note: We intentionally do NOT modify existing release body on refresh.)

for f in "$ASSET_TARBALL" "$ASSET_KEYCHAIN" "$ASSET_MAN"; do
  [ -f "$f" ] || fail "Missing asset file $f"
  case $(basename "$f") in
    keychain-$VER.tar.gz) pname="keychain-$VER.tar.gz";;
    keychain) pname="keychain";;
    keychain.1) pname="keychain.1";;
    *) if echo "$f" | grep -q "keychain-$VER.tar.gz"; then pname="keychain-$VER.tar.gz"; fi
       if echo "$f" | grep -q "/keychain$"; then pname="keychain"; fi
       if echo "$f" | grep -q "/keychain.1$"; then pname="keychain.1"; fi
       [ -n "${pname:-}" ] || fail "Could not determine asset publish name for $f";;
  esac
  curl -sS -X POST \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Content-Type: application/octet-stream" \
    --data-binary @"$f" \
    "https://uploads.github.com/repos/${GITHUB_REPOSITORY}/releases/$rel_id/assets?name=$pname" >/dev/null
  echo " uploaded $pname (from $f)"
done

echo "Assets refreshed for release $VER."
