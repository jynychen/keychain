# Keychain Release Steps

This document defines the standard release process. Releases use **numeric tags only** (no leading `v`). Example: `2.9.6`.

## 1. When to Bump
- Patch (X.Y.Z -> X.Y.Z+1): Documentation, branding, hardening w/o behavior change.
- Minor (X.Y -> X.Y+1): User-visible new features, option additions.
- Major (X -> X+1): Backward-incompatible changes, removed options.

## 2. Pre-Flight Checklist
1. Working tree clean (`git status`).
2. Update `ChangeLog.md`: add new section at top: `## keychain <version> (<DD Mon YYYY>)`.
3. Update `VERSION` file to match new version.
4. Ensure only intentional `funtoo.org` references (historical note in docs only).
5. Decide if any last-minute man page edits are required.

## 3. Build Artifacts
Manual build (optional; `make release` now auto-rebuilds prerequisites):
```
make clean && make keychain-$(cat VERSION).tar.gz
```
`make release` or `make release-refresh` will ensure these artifacts exist automatically.

Artifacts:
- `keychain` (executable wrapper, not committed)
- `keychain.1` (man page)
- `keychain.spec`
- `keychain.txt`
- `keychain-<version>.tar.gz`

## 4. Local Sanity Tests
```
./keychain --version
./keychain --help | head -20
grep -R "github.com/funtoo/keychain" . && echo "(should be zero results)"
```
Check man page header `.TH` line for correct date/version and updated center URL (GitHub canonical).

## 5. Tagging
Signed (preferred):
```
git tag -s $(cat VERSION) -m "$(cat VERSION)"
```
Unsigned:
```
git tag $(cat VERSION)
```
Push:
```
git push
git push --tags
```

## 6. Orchestrated Release Path (Preferred)
Run:
```
make release   # for first publication
```
You will see:
1. Local build presence check (or build via prerequisites).
2. CI artifact fetch (MANDATORY). Failure to retrieve artifacts aborts; you must wait for the workflow to finish.
3. Normalized comparison phase (LOCAL vs CI build):
   * `keychain` – raw sha256 digest compare.
   * `keychain.1` – raw hash first; if different, re-compare with the Pod::Man auto-generated first line stripped. A normalized match counts as a match (header differences ignored).
   * `keychain-<version>.tar.gz` – unpack both tarballs; compare sorted file list and per-file sha256 (man page internally also normalized on first line). Blob-level tar/gzip metadata differences (mtime, uid, compression variance) are ignored if internal contents match.
   Outcome:
     - If all artifacts match (raw or normalized) -> Release uses the CI artifact files directly (local artifacts remain untouched for auditing).
     - If any real content mismatch exists -> Abort.
     - Override (discouraged) to force publish local artifacts despite mismatch: `KEYCHAIN_FORCE_LOCAL=1 make release`
   (Use corresponding `... make release-refresh` for refresh mode.)
4. Display of generated release notes (ChangeLog excerpt + provenance table preview).
5. Y/N confirmation prompt.
6. Release creation (or refresh) + asset upload + release notes (re)generation with provenance table via GitHub API.

## 7. Automated Path (Tag-Driven Workflow)
Pushing a tag matching `X.Y.Z` triggers `.github/workflows/release.yml` which:
- Validates `VERSION` matches tag.
- Builds artifacts inside a Debian container.
- Extracts ChangeLog section into `.release-notes.md`.
- Uploads a private workflow artifact bundle (NOT a published GitHub Release).

Publication only occurs when you run `make release` (or refresh) locally; CI never auto-publishes.

## 8. Fast-Fail vs Refresh
Targets:
- `make release` – Orchestrated create (fails if release exists) with digest validation & confirmation.
- `make release-refresh` – Same flow but updates existing release assets AND regenerates release notes (including provenance table).

Both require `GITHUB_TOKEN` (repo scope) exported in the environment.

## 9. Refresh Scenario Workflow
If you forgot something (docs only, same version):
```
# Edit ChangeLog.md (if you need to adjust text; refresh will regenerate release notes from current ChangeLog plus provenance.)
# Rebuild if needed (optional): make keychain-$(cat VERSION).tar.gz
make release-refresh
```
You will again get CI fetch attempt, comparisons, preview, and prompt.
If functional change needed after publishing: bump version, amend ChangeLog, retag.

## 10. Rollback
If a bad tag was pushed:
```
git push origin :refs/tags/<version>
# Optionally delete the GitHub release in the UI.
# Fix issues, retag and push again.
```

## 11. Future Hardening (Planned)
- ShellCheck + POSIX lint gating before release.
- GPG signing of tarball & man page.
- Audit target (`make audit-brand`) to fail on unexpected deprecated domains.
- Security hardening sweep (tracked separately).

## 12. Changelog Extraction (Reference)
Pseudo-command used by workflow:
```
version=$(cat VERSION)
awk -v ver="$version" '/^## keychain 'ver' /{f=1;print;next} /^## keychain /&&f && $0 !~ ver {exit} f' ChangeLog.md
```

## 13. Verification Matrix
| Item | Location | Must Match |
|------|----------|-----------|
| Version tag | git tag | `VERSION` file |
| Wrapper script | `keychain` | contains version string |
| Man page header | `keychain.1` | version/date/center URL |
| Tarball name | `keychain-<version>.tar.gz` | version |

## 14. Minimal Quick Release Recap
```
$EDITOR ChangeLog.md VERSION
make clean && make keychain-$(cat VERSION).tar.gz
./keychain --version
git tag -s $(cat VERSION) -m "$(cat VERSION)"
git push && git push --tags
# Create GitHub release, upload assets
```

---
Maintained as of 06 Sep 2025 (CI artifacts canonical: local artifacts are never overwritten; only source path selection differs).
