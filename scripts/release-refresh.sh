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
for f in keychain-$VER.tar.gz keychain keychain.1; do
  [ -f "$f" ] || fail "Missing asset $f"
  curl -sS -X POST \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Content-Type: application/octet-stream" \
    --data-binary @"$f" \
    "https://uploads.github.com/repos/${GITHUB_REPOSITORY}/releases/$rel_id/assets?name=$(basename "$f")" >/dev/null
  echo " uploaded $f"
done

echo "Assets refreshed for release $VER."
