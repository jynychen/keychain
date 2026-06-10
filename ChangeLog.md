# ChangeLog

## 3.0.0_beta1

Initial public beta of Keychain 3.x.

Keychain 3 is a ground-up Python 3 rewrite of Daniel Robbins' long-running
SSH/GPG agent manager. The release preserves the traditional single-file
deployment model through `keychain.pyz`, while replacing the historical
Bourne shell implementation with a tested, auditable Python package.

Highlights:

- Ships as a standalone `keychain.pyz` with no third-party runtime
  dependencies.
- Requires Python 3.9 or newer at runtime; the zipapp bootstrap can re-exec
  into a newer `python3.NN` on systems where `/usr/bin/env python3` is below
  the floor.
- Adds an action-oriented command surface such as `keychain add`,
  `keychain agent start`, `keychain agent stop`, `keychain list`,
  `keychain env`, `keychain inspect`, `keychain help`, and `keychain man`.
- Keeps keychain 2.x-style invocations working through an explicit
  compatibility layer.
- Embeds documentation in the zipapp; use `keychain man` and
  `keychain man --list` to browse it.
- Uses a default-deny model for `KEYCHAIN_*` environment variables; pass
  `--allow-env` / `-E` when legacy environment-variable behavior is desired.
- Releases under GPLv3 for the 3.x series. Keychain 2.x remains GPLv2.

Known beta notes:

- WSL login-shell startup can run keychain in a noninteractive/no-TTY context
  when invoked by automation. This may fall through to `ssh_askpass`; stale
  WSL `/tmp/ssh-*` sockets and hostname-specific pidfiles are tracked for
  follow-up polish.
