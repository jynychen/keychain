#!/bin/sh
# Common helper functions for release automation.
# Requires: curl, jq (jq optional for nicer parsing; if absent we try raw parsing.)

set -eu

api() {
  # api <method> <path> [datafile]
  method=$1; shift
  path=$1; shift
  url="https://api.github.com/repos/${GITHUB_REPOSITORY}${path}"
  hdrs="-H Authorization: Bearer ${GITHUB_TOKEN} -H Accept: application/vnd.github+json"
  if [ $# -gt 0 ]; then
    data="@${1}"; curl -fsSL -X "$method" $hdrs --data "$data" "$url"
  else
    curl -fsSL -X "$method" $hdrs "$url"
  fi
}

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing required tool: $1" >&2; exit 1; }; }

extract_notes() {
  ver=$1
  awk -v ver="$ver" 'BEGIN{printed=0} /^## keychain "ver" /{printed=1;print;next} /^## keychain / && printed {exit} printed {print}' ChangeLog.md
}

fail() { echo "Error: $*" >&2; exit 1; }

# Validate environment
[ -n "${GITHUB_TOKEN:-}" ] || fail "GITHUB_TOKEN not set"
[ -n "${GITHUB_REPOSITORY:-}" ] || fail "GITHUB_REPOSITORY not set (e.g. danielrobbins/keychain)"
need curl
