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

# Pre-compute artifact paths (may be CI paths when orchestrated)
ASSET_KEYCHAIN=${KEYCHAIN_ASSET_KEYCHAIN:-keychain}
ASSET_MAN=${KEYCHAIN_ASSET_MAN:-keychain.1}
ASSET_TARBALL=${KEYCHAIN_ASSET_TARBALL:-keychain-$VER.tar.gz}

# Append provenance table with sha256 and tag commit at bottom of notes
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
  } >> "$notes_file"
fi

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

for f in "$ASSET_TARBALL" "$ASSET_KEYCHAIN" "$ASSET_MAN"; do
  [ -f "$f" ] || fail "Missing asset file $f"
  # Determine publish name (basename should remain canonical filenames)
  case $(basename "$f") in
    keychain-$VER.tar.gz) pname="keychain-$VER.tar.gz";;
    keychain) pname="keychain";;
    keychain.1) pname="keychain.1";;
    *) # If path is different (e.g., CI dir), map by type heuristics
       if echo "$f" | grep -q "keychain-$VER.tar.gz"; then pname="keychain-$VER.tar.gz"; fi
       if echo "$f" | grep -q "/keychain$"; then pname="keychain"; fi
       if echo "$f" | grep -q "/keychain.1$"; then pname="keychain.1"; fi
       [ -n "${pname:-}" ] || fail "Could not determine asset publish name for $f";
       ;;
  esac
  curl -sS -X POST \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Content-Type: application/octet-stream" \
    --data-binary @"$f" \
    "https://uploads.github.com/repos/${GITHUB_REPOSITORY}/releases/$(curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" https://api.github.com/repos/${GITHUB_REPOSITORY}/releases/tags/$VER | jq '.id')/assets?name=$pname" >/dev/null
  echo " uploaded $pname (from $f)"
done

echo "Release $VER created successfully."
