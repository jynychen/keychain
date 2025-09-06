#!/bin/sh
# Orchestrated release creation/refresh with:
# 1. Local build presence check (already performed via Makefile prereqs)
# 2. CI artifact fetch (mandatory)
# 3. Digest comparison (local vs CI artifacts) with normalization rules
# 4. Selection of artifact SOURCE PATHS (never mutating local originals):
#      * If all artifacts match (allowing normalized equality) AND no override -> USE CI PATHS
#      * If KEYCHAIN_FORCE_LOCAL=1 -> USE LOCAL PATHS (even if mismatches)
#      * Otherwise any real mismatch aborts
# 5. Display extracted release notes for confirmation
# 6. Create or refresh release using chosen artifact paths
# Usage: release-orchestrate.sh create|refresh <version>
set -eu

MODE=${1:?usage: release-orchestrate.sh create|refresh <version>}
VER=${2:?usage: release-orchestrate.sh create|refresh <version>}
REPO=${GITHUB_REPOSITORY:-danielrobbins/keychain}

[ "$(cat VERSION)" = "$VER" ] || { echo "VERSION file mismatch ($(cat VERSION)) != $VER" >&2; exit 1; }
[ -n "${GITHUB_TOKEN:-}" ] || { echo "GITHUB_TOKEN not set" >&2; exit 1; }

# 1. Ensure local assets exist
for f in keychain-$VER.tar.gz keychain keychain.1; do
  [ -f "$f" ] || { echo "Missing local asset: $f" >&2; exit 1; }
  done

# 2. Fetch CI artifacts (MANDATORY)
CI_DIR=".ci-artifacts-$VER"
rm -rf "$CI_DIR"
echo "Fetching CI artifacts for $VER (mandatory step)..." >&2
if ! ./scripts/fetch-ci-artifacts.sh "$VER" "$CI_DIR"; then
  echo "ERROR: Unable to retrieve CI artifacts for $VER. Release aborted." >&2
  echo "Hint: Ensure the GitHub Actions 'release' workflow for tag $VER has completed successfully." >&2
  echo "       Re-run 'make release' once artifacts are available." >&2
  exit 1
fi
echo "CI artifacts retrieved." >&2

calc_sha256() { sha256sum "$1" | awk '{print $1}'; }

diff_flag=0
echo "Digest comparison (normalized where applicable):"

compare_tar_content() {
  local local_tar=$1 ci_tar=$2
  local tmp_local tmp_ci
  tmp_local=$(mktemp -d)
  tmp_ci=$(mktemp -d)
  # Extract quietly
  tar xzf "$local_tar" -C "$tmp_local" 2>/dev/null || return 2
  tar xzf "$ci_tar" -C "$tmp_ci" 2>/dev/null || return 2
  # Determine root (expect exactly one directory named keychain-$VER)
  local root="keychain-$VER"
  if [ ! -d "$tmp_local/$root" ] || [ ! -d "$tmp_ci/$root" ]; then
    echo "  keychain-$VER.tar.gz: unexpected directory layout inside tar" >&2
    return 3
  fi
  # List files (regular only) relative to root
  local lf cf
  lf=$( (cd "$tmp_local/$root" && find . -type f -print | LC_ALL=C sort) )
  cf=$( (cd "$tmp_ci/$root" && find . -type f -print | LC_ALL=C sort) )
  if [ "$lf" != "$cf" ]; then
    echo "  keychain-$VER.tar.gz: file list differs" >&2
    return 4
  fi
  # Hash each file
  local mismatch=0
  while IFS= read -r rel; do
    [ -z "$rel" ] && continue
    local h1 h2
    # For keychain.1 apply normalization (skip first line) before comparing to avoid Pod::Man header diffs.
    if [ "$(basename "$rel")" = "keychain.1" ]; then
      h1=$(tail -n +2 "$tmp_local/$root/$rel" | sha256sum | awk '{print $1}')
      h2=$(tail -n +2 "$tmp_ci/$root/$rel" | sha256sum | awk '{print $1}')
      if [ "$h1" != "$h2" ]; then
        echo "  keychain-$VER.tar.gz: content mismatch in $rel (beyond header)" >&2
        mismatch=1
      fi
    else
      h1=$(sha256sum "$tmp_local/$root/$rel" | awk '{print $1}')
      h2=$(sha256sum "$tmp_ci/$root/$rel" | awk '{print $1}')
      if [ "$h1" != "$h2" ]; then
        echo "  keychain-$VER.tar.gz: content mismatch in $rel" >&2
        mismatch=1
      fi
    fi
  done <<EOF
$lf
EOF
  if [ $mismatch -eq 0 ]; then
    # Even if tarball blob hashes differ, content matches.
    return 0
  else
    return 5
  fi
}

# Process artifacts with specialized logic
for artifact in keychain keychain.1 keychain-$VER.tar.gz; do
  if [ ! -f "$CI_DIR/$artifact" ]; then
    printf '  %-20s CI copy missing; comparison failed (abort)\n' "$artifact"
    diff_flag=1
    continue
  fi
  case "$artifact" in
    keychain)
      L=$(calc_sha256 "$artifact"); R=$(calc_sha256 "$CI_DIR/$artifact")
      if [ "$L" = "$R" ]; then
        printf '  %-20s %s (match)\n' "$artifact" "$L"
      else
        printf '  %-20s LOCAL %s != CI %s  *DIFF*\n' "$artifact" "$L" "$R"
        diff_flag=1
      fi
      ;;
    keychain.1)
      # Direct hash first
      L=$(calc_sha256 "$artifact"); R=$(calc_sha256 "$CI_DIR/$artifact")
      if [ "$L" = "$R" ]; then
        printf '  %-20s %s (match)\n' "$artifact" "$L"
      else
        # Normalize and compare ignoring Pod::Man header line.
        if diff -u <(tail -n +2 "$artifact") <(tail -n +2 "$CI_DIR/$artifact") >/dev/null 2>&1; then
          printf '  %-20s (normalized match ignoring Pod::Man header)\n' "$artifact"
        else
          printf '  %-20s LOCAL %s != CI %s  *DIFF* (content mismatch beyond header)\n' "$artifact" "$L" "$R"
          diff_flag=1
        fi
      fi
      ;;
    keychain-$VER.tar.gz)
      if compare_tar_content "$artifact" "$CI_DIR/$artifact"; then
        # If tar blob hash matches display it; else note normalized match.
        L=$(calc_sha256 "$artifact"); R=$(calc_sha256 "$CI_DIR/$artifact")
        if [ "$L" = "$R" ]; then
          printf '  %-20s %s (match)\n' "$artifact" "$L"
        else
          printf '  %-20s (content match; tar/gzip metadata differ)\n' "$artifact"
        fi
      else
        printf '  %-20s *CONTENT DIFF* (see above messages)\n' "$artifact"
        diff_flag=1
      fi
      ;;
  esac
done

if [ $diff_flag -ne 0 ]; then
  echo
  echo "Artifact mismatch detected between LOCAL build and CI (Debian) build." >&2
  echo "Release aborted (provenance mismatch) unless KEYCHAIN_FORCE_LOCAL=1 is set." >&2
  echo
  echo "Copy/paste diff commands:" >&2
  echo "  VER=$VER; CI_DIR=$CI_DIR" >&2
  echo "  diff -u keychain \"$CI_DIR/keychain\"" >&2
  echo "  diff -u keychain.1 \"$CI_DIR/keychain.1\"" >&2
  echo "  diff -u <(tar tzf keychain-$VER.tar.gz | sort) <(tar tzf $CI_DIR/keychain-$VER.tar.gz | sort)" >&2
  echo "  mkdir -p /tmp/kc-local /tmp/kc-ci && tar xzf keychain-$VER.tar.gz -C /tmp/kc-local && tar xzf $CI_DIR/keychain-$VER.tar.gz -C /tmp/kc-ci && diff -ru /tmp/kc-local/keychain-$VER /tmp/kc-ci/keychain-$VER" >&2
  echo
  if [ "${KEYCHAIN_FORCE_LOCAL:-}" = 1 ]; then
    echo "KEYCHAIN_FORCE_LOCAL=1 set: proceeding using LOCAL artifacts despite mismatches." >&2
  else
    exit 1
  fi
fi

# Decide which artifact paths to publish (never overwrite local originals)
if [ "${KEYCHAIN_FORCE_LOCAL:-}" = 1 ]; then
  KEYCHAIN_ASSET_KEYCHAIN="keychain"
  KEYCHAIN_ASSET_MAN="keychain.1"
  KEYCHAIN_ASSET_TARBALL="keychain-$VER.tar.gz"
  echo "Source selection: USING LOCAL artifacts (override)." >&2
else
  # All artifacts matched (raw or normalized) -> use CI versions
  KEYCHAIN_ASSET_KEYCHAIN="$CI_DIR/keychain"
  KEYCHAIN_ASSET_MAN="$CI_DIR/keychain.1"
  KEYCHAIN_ASSET_TARBALL="$CI_DIR/keychain-$VER.tar.gz"
  echo "Source selection: USING CI artifacts (canonical)." >&2
fi
export KEYCHAIN_ASSET_KEYCHAIN KEYCHAIN_ASSET_MAN KEYCHAIN_ASSET_TARBALL

# 3. Generate full release notes (ChangeLog excerpt + provenance) for preview
NOTES_FILE=$(mktemp)
./scripts/release-notes.sh "$VER" "$NOTES_FILE" || { echo "Failed to generate release notes preview" >&2; exit 1; }

echo
echo "================ Release Notes Preview (generated) ======================"
sed 's/^/| /' "$NOTES_FILE"
echo "========================================================================="

printf 'Continue with %s of %s? (Y/N): ' "$MODE" "$VER"
read ans < /dev/tty || ans=N
case "$ans" in
  Y|y) echo "Continuing...";;
  *) echo "Aborted by user."; exit 1;;
 esac

# 4. Publish / refresh
if [ "$MODE" = create ]; then
  ./scripts/release-create.sh "$VER"
else
  ./scripts/release-refresh.sh "$VER"
fi

echo "Done."
