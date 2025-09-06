#!/bin/sh
# Create a new GitHub release (fails if it exists) and upload assets.
set -eu
VER=${1:?usage: release-create.sh <version>}
GITHUB_REPOSITORY=${GITHUB_REPOSITORY:-danielrobbins/keychain}
. "$(dirname "$0")/release-common.sh"

[ "$(cat VERSION)" = "$VER" ] || fail "VERSION file mismatch ($(cat VERSION) != $VER)"

notes_file=$(mktemp)
awk -v ver="$VER" '/^## keychain '"$VER"' /{f=1;print;next} /^## keychain / && f && $0 !~ ver {exit} f' ChangeLog.md > "$notes_file"
[ -s "$notes_file" ] || fail "Could not extract changelog section for $VER"

echo "Creating release $VER"
json=$(mktemp)
cat >"$json" <<EOF
{
  "tag_name": "$VER",
  "name": "keychain $VER",
  "body": $(jq -Rs . < "$notes_file"),
  "draft": false,
  "prerelease": false,
  "generate_release_notes": false
}
EOF

# Create release (will fail if already exists)
api POST /releases "$json" >/dev/null || fail "Failed to create release (maybe it already exists?)"

echo "Uploading assets..."
for f in keychain-$VER.tar.gz keychain keychain.1; do
  [ -f "$f" ] || fail "Missing asset $f"
  curl -sS -X POST \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Content-Type: application/octet-stream" \
    --data-binary @"$f" \
    "https://uploads.github.com/repos/${GITHUB_REPOSITORY}/releases/$(curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" https://api.github.com/repos/${GITHUB_REPOSITORY}/releases/tags/$VER | jq '.id')/assets?name=$(basename "$f")" >/dev/null
  echo " uploaded $f"
done

echo "Release $VER created successfully."
