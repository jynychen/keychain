#!/bin/sh
# Fetch latest workflow artifacts for the given version tag using the GitHub API.
# Usage: GITHUB_TOKEN=... GITHUB_REPOSITORY=owner/repo ./scripts/fetch-ci-artifacts.sh <version> <destdir>
set -eu
VER=${1:?usage: fetch-ci-artifacts.sh <version> <destdir>}
DEST=${2:?usage: fetch-ci-artifacts.sh <version> <destdir>}
REPO=${GITHUB_REPOSITORY:?GITHUB_REPOSITORY not set}
[ -n "${GITHUB_TOKEN:-}" ] || { echo "GITHUB_TOKEN not set" >&2; exit 1; }

# Find workflow run for this tag (latest by created_at)
# We assume workflow file name 'release.yml'.
RUNS_JSON=$(curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" "https://api.github.com/repos/$REPO/actions/runs?per_page=50")
RUN_ID=$(printf '%s' "$RUNS_JSON" | jq -r --arg ver "$VER" '.workflow_runs | map(select(.head_branch == $ver or .display_title == $ver or .head_sha != null)) | map(select(.name=="release")) | map(select(.head_branch==$ver)) | sort_by(.created_at) | last.id')
[ "$RUN_ID" != "null" ] || { echo "No workflow run found for tag $VER" >&2; exit 1; }

ARTIFACTS=$(curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" "https://api.github.com/repos/$REPO/actions/runs/$RUN_ID/artifacts")
ART_ID=$(printf '%s' "$ARTIFACTS" | jq -r '.artifacts[] | select(.name | test("keychain-")) | .id' | tail -1)
[ -n "$ART_ID" ] || { echo "No artifacts found for run $RUN_ID" >&2; exit 1; }

TMPZIP=$(mktemp)
curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" -L "https://api.github.com/repos/$REPO/actions/artifacts/$ART_ID/zip" -o "$TMPZIP"
mkdir -p "$DEST"
unzip -qo "$TMPZIP" -d "$DEST"
rm -f "$TMPZIP"

echo "Fetched CI artifacts for $VER into $DEST" >&2
