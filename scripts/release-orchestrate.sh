#!/bin/sh
# Orchestrated release creation/refresh with:
# 1. Local build (already performed via Makefile prereqs)
# 2. CI artifact fetch
# 3. Digest comparison (local vs CI artifacts)
# 4. Display extracted release notes for confirmation
# 5. Create or refresh release using base scripts
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
echo "Digest comparison (sha256):"
for artifact in keychain-$VER.tar.gz keychain keychain.1; do
  if [ -f "$CI_DIR/$artifact" ]; then
    L=$(calc_sha256 "$artifact")
    R=$(calc_sha256 "$CI_DIR/$artifact")
    if [ "$L" = "$R" ]; then
      printf '  %-20s %s (match)\n' "$artifact" "$L"
    else
      printf '  %-20s LOCAL %s != CI %s  *DIFF*\n' "$artifact" "$L" "$R"
      diff_flag=1
    fi
  else
    printf '  %-20s CI copy missing; comparison failed (abort)\n' "$artifact"
    diff_flag=1
  fi
done

if [ $diff_flag -ne 0 ]; then
  echo
  echo "Artifact mismatch detected between LOCAL build and CI (Debian) build." >&2
  echo "Release aborted to preserve deterministic provenance." >&2
  echo
  echo "Copy/paste diff commands:" >&2
  echo "  VER=$VER; CI_DIR=$CI_DIR" >&2
  echo "  diff -u keychain \"$CI_DIR/keychain\"" >&2
  echo "  diff -u keychain.1 \"$CI_DIR/keychain.1\"" >&2
  echo "  diff -u <(tar tzf keychain-$VER.tar.gz | sort) <(tar tzf $CI_DIR/keychain-$VER.tar.gz | sort)" >&2
  echo "  mkdir -p /tmp/kc-local /tmp/kc-ci && tar xzf keychain-$VER.tar.gz -C /tmp/kc-local && tar xzf $CI_DIR/keychain-$VER.tar.gz -C /tmp/kc-ci && diff -ru /tmp/kc-local/keychain-$VER /tmp/kc-ci/keychain-$VER" >&2
  echo
  echo "Override options (explicit user intent required):" >&2
  echo "  Use LOCAL artifacts: KEYCHAIN_FORCE_LOCAL=1 make $( [ "$MODE" = refresh ] && echo release-refresh || echo release )" >&2
  echo "  Adopt CI artifacts: KEYCHAIN_ADOPT_CI=1 make $( [ "$MODE" = refresh ] && echo release-refresh || echo release )" >&2
  echo
  if [ "${KEYCHAIN_FORCE_LOCAL:-}" = 1 ]; then
    echo "KEYCHAIN_FORCE_LOCAL=1 set: proceeding with LOCAL artifacts despite mismatch." >&2
  elif [ "${KEYCHAIN_ADOPT_CI:-}" = 1 ]; then
    echo "KEYCHAIN_ADOPT_CI=1 set: replacing local artifacts with CI versions where available." >&2
    for a in keychain-$VER.tar.gz keychain keychain.1; do
      [ -f "$CI_DIR/$a" ] && cp -f "$CI_DIR/$a" "$a"
    done
  else
    exit 1
  fi
fi

# 3. Extract release notes section for confirmation
NOTES_FILE=$(mktemp)
awk -v ver="$VER" '/^## keychain '"$VER"' /{f=1;print;next} /^## keychain / && f && $0 !~ ver {exit} f' ChangeLog.md > "$NOTES_FILE"
[ -s "$NOTES_FILE" ] || { echo "Could not extract changelog section for $VER" >&2; exit 1; }

echo
echo "================ Release Notes Preview (from ChangeLog.md) ================"
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
