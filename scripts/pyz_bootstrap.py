# SPDX-License-Identifier: GPL-3.0-only
"""Zipapp entry point with a re-exec bootstrap.

This module is copied verbatim to ``build/pyz-stage/__main__.py`` by the
``keychain.pyz`` Makefile target. It runs *before* any keychain code is
imported, on whatever Python ``/usr/bin/env python3`` happens to resolve
to. Its job is to make sure we end up running on a Python that can
actually execute the package (currently 3.9+).

Why a Python bootstrap instead of a shell shebang trick:

* ``#!/usr/bin/env python3`` is the only shebang form that works on both
  POSIX systems and Windows (via the ``py.exe`` PEP 397 launcher and
  ``.pyz`` file association). Polyglot sh/python preambles do not run on
  Windows at all.
* Hardcoding a fallback chain like ``python3.13 || python3.12 || ...``
  in shell grows linearly with each Python release and goes stale; this
  module discovers ``python3.NN`` binaries dynamically so future releases
  Just Work.
* On modern systems (where ``python3`` already satisfies the floor) this
  costs one tuple comparison: no PATH walk, no re-exec.
* On RHEL 8 / Rocky 8 (where ``/usr/bin/python3`` is 3.6.8 but the user
  installed ``python39``/``python311``/``python313`` via AppStream
  modules), we ``os.execv`` into the newest available interpreter.
"""

from __future__ import annotations

import os
import sys

# Must match the floor declared in pyproject.toml's ``requires-python``
# and the version guard in ``keychain/__init__.py``. Bump all three
# together when the floor moves.
_FLOOR = (3, 9)


def _find_newer_python() -> str | None:
    """Return the path to the newest ``python3.NN >= floor`` on PATH.

    Returns ``None`` if no suitable interpreter is found, in which case
    the caller falls through to the version-floor guard in
    ``keychain/__init__.py`` and exits with a friendly error.
    """
    # Avoid importing shutil here -- it is ~150 lines of stdlib that we
    # do not need on the fast path. os.environ + os.path is enough.
    seen: set[str] = set()
    best: tuple[tuple[int, int], str] | None = None
    path_sep = os.pathsep
    is_win = os.name == "nt"
    exe_suffix = ".exe" if is_win else ""

    for directory in os.environ.get("PATH", "").split(path_sep):
        if not directory or directory in seen:
            continue
        seen.add(directory)
        try:
            entries = os.listdir(directory)
        except OSError:
            continue
        for entry in entries:
            # Match python3.NN[.exe], reject python3.NN-config and friends.
            stem = entry[: -len(exe_suffix)] if exe_suffix and entry.endswith(exe_suffix) else entry
            if not stem.startswith("python3."):
                continue
            tail = stem[len("python3.") :]
            if not tail.isdigit():
                continue
            minor = int(tail)
            version = (3, minor)
            if version < _FLOOR:
                continue
            full = os.path.join(directory, entry)
            if not (os.path.isfile(full) and os.access(full, os.X_OK)):
                continue
            if best is None or version > best[0]:
                best = (version, full)
    return best[1] if best else None


def _maybe_reexec() -> None:
    """If the current interpreter is below the floor, exec into a newer one."""
    if sys.version_info[:2] >= _FLOOR:
        return
    newer = _find_newer_python()
    if newer is None:
        # Let keychain/__init__.py's import-time guard print the friendly
        # remediation message and exit 2.
        return
    # Resolve to a real path so the loop-prevention check below catches
    # the case where ``newer`` is a symlink to ``sys.executable``.
    try:
        if os.path.realpath(newer) == os.path.realpath(sys.executable):
            return
    except OSError:
        return
    # os.execv replaces this process; PID, signals, env, stdio, exit code
    # all flow through cleanly.
    os.execv(newer, [newer, *sys.argv])


_maybe_reexec()

from keychain.main import main  # noqa: E402  -- must follow the bootstrap

if __name__ == "__main__":
    main()
