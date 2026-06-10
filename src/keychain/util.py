# SPDX-License-Identifier: GPL-3.0-only
"""Shared utilities: exceptions, output, locking, small POSIX helpers.

Targets Python 3.9+ (RHEL 8 users opt in via ``dnf module install python39``).
"""

from __future__ import annotations

import contextlib
import ctypes
import os
import socket
import stat
import subprocess
import sys
import time
from collections.abc import Iterable
from pathlib import Path
from typing import Any, Union, cast

try:
    import pwd as _pwd_impl  # POSIX
except ImportError:  # Windows / Git Bash on native Python
    _pwd: Any | None = None
else:
    _pwd = _pwd_impl


PathLike = Union[str, "os.PathLike[str]"]


# ---------------------------------------------------------------------------
# Exceptions
# ---------------------------------------------------------------------------


class KeychainError(Exception):
    """Raised for user-visible fatal errors. Caught once in :func:`cli.main`."""


# ---------------------------------------------------------------------------
# Output / colors / themes -- moved to keychain.output. Re-exported here so
# ``from keychain.util import Output`` keeps working through the deprecation
# window. New code should import from ``keychain.output`` directly.
# ---------------------------------------------------------------------------

from .output.core import (  # noqa: E402,F401  (re-export for back-compat)
    DEFAULT_THEME,
    THEMES,
    Output,
    Span,
    stderr_supports_unicode,
)


# Back-compat: docs/render.py imports ``resolve_theme`` and uses the
# legacy-palette dict shape (``{'CYANN': '...', 'OFF': '...'}``). The new
# :class:`~keychain.output.Theme` exposes that as ``Theme.palette``.
def resolve_theme(name):  # type: ignore[no-untyped-def]
    """Return the legacy palette dict for *name*; fall back to default."""
    if name:
        key = name.strip().lower()
        if key in THEMES:
            return dict(THEMES[key].palette)
    return dict(THEMES[DEFAULT_THEME].palette)


# ---------------------------------------------------------------------------
# Subprocess wrapper
# ---------------------------------------------------------------------------


def run(
    cmd: list[str],
    env: dict[str, str] | None = None,
    input_: str | None = None,
    timeout: float | None = None,
    c_locale: bool = True,
) -> subprocess.CompletedProcess:
    """Run ``cmd``, capturing text output. Returns ``CompletedProcess``.

    ``c_locale=True`` forces ``LC_ALL=C`` for the child only, so the caller's
    locale is never mutated. Raises :class:`FileNotFoundError` if the binary
    is missing -- callers decide how to react.
    """
    run_env = {**os.environ, **(env or {})} | ({"LC_ALL": "C"} if c_locale else {})
    return subprocess.run(
        cmd,
        input=input_,
        env=run_env,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=timeout,
        check=False,
    )


# ---------------------------------------------------------------------------
# Lockfile
# ---------------------------------------------------------------------------


def _lock_content() -> str:
    """Lock-file payload: ``hostname:pid``.

    Including the hostname makes the lock NFS-safe: a reader on a different
    host that finds a lock written here will see a hostname mismatch and
    leave the lock alone rather than running ``os.kill`` against an
    unrelated local process that happens to share the same PID.
    """
    return f"{socket.gethostname()}:{os.getpid()}"


class LockFile:
    """Atomic ``O_CREAT | O_EXCL`` PID lock. Use as a context manager.

    ``no_lock=True`` makes the manager a no-op (still safe to use). The acquired
    state is exposed via :attr:`acquired` and the lock is released on exit.
    """

    __slots__ = ("path", "no_lock", "wait", "out", "acquired")

    def __init__(self, path: PathLike, no_lock: bool, wait: int, out: Output) -> None:
        self.path = Path(path)
        self.no_lock = no_lock
        self.wait = max(0, int(wait))
        self.out = out
        self.acquired = False

    # ---- context manager ----------------------------------------------
    def __enter__(self) -> LockFile:
        if self.no_lock:
            self.acquired = True  # granted without writing a file
            return self
        if self._acquire():
            return self
        self.out.info(f"Waiting {self.wait} seconds for lock...")
        deadline = time.monotonic() + self.wait
        while time.monotonic() < deadline:
            if self._acquire():
                return self
            time.sleep(0.1)
        # Final break-the-glass attempt: drop a stale lock and retry once.
        # With wait=0, force-takeover is the default behavior (gap §3.6).
        # With wait>0, only unlink if the lock is stale to avoid stomping
        # on a valid lock held by another process that happened to create
        # the file during the wait loop.
        if self.wait == 0 or not self._lock_is_live():
            with contextlib.suppress(OSError):
                self.path.unlink()
        if not self._acquire():
            raise KeychainError(f"could not acquire lock {self.path}")
        return self

    def __exit__(self, exc_type, exc, tb):
        self.release()
        return False

    # ---- internals -----------------------------------------------------
    def _acquire(self) -> bool:
        try:
            fd = os.open(str(self.path), os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        except FileExistsError:
            # Lock exists; honour it only if the owning process is still live.
            if self._lock_is_live():
                return False
            with contextlib.suppress(OSError):
                self.path.unlink()
            try:
                fd = os.open(str(self.path), os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
            except OSError:
                return False
        try:
            os.write(fd, _lock_content().encode())
        finally:
            os.close(fd)
        self.acquired = True
        return True

    def _lock_is_live(self) -> bool:
        """Return True if the existing lock file belongs to a live process.

        The lock file payload is ``hostname:pid``.  If the hostname differs
        from ours (NFS-mounted home directory shared across hosts) we cannot
        call ``os.kill`` against a remote PID, so we conservatively treat the
        lock as live and leave it alone.  A legacy file containing only a
        plain PID (no ``:``) is treated as originating on the local host.
        """
        try:
            raw = self.path.read_text(encoding="utf-8").strip()
        except OSError:
            return False
        hostname, sep, pid_s = raw.partition(":")
        if not sep:
            # Legacy plain-PID format -- assume local host.
            hostname, pid_s = socket.gethostname(), raw
        try:
            owner_pid = int(pid_s)
        except ValueError:
            return False
        if not owner_pid:
            return False
        if hostname != socket.gethostname():
            # Lock is held on a different host; cannot verify liveness.
            return True
        return pid_alive(owner_pid)

    def release(self) -> None:
        if self.acquired:
            if not self.no_lock:
                with contextlib.suppress(OSError):
                    self.path.unlink()
            self.acquired = False


# ---------------------------------------------------------------------------
# Small POSIX helpers
# ---------------------------------------------------------------------------


def pid_alive(pid: int) -> bool:
    """Best-effort process liveness probe."""
    if pid <= 0:
        return False
    if os.name == "nt":
        kernel32 = cast(Any, ctypes).windll.kernel32
        handle = kernel32.OpenProcess(0x1000, False, pid)
        if not handle:
            return False
        try:
            exit_code = ctypes.c_ulong()
            if not kernel32.GetExitCodeProcess(handle, ctypes.byref(exit_code)):
                return False
            return exit_code.value == 259
        finally:
            kernel32.CloseHandle(handle)
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    return True


def get_owner(path: PathLike) -> str:
    """Return the username that owns *path*, or '' on error / non-POSIX."""
    if _pwd is None:
        return ""
    try:
        return _pwd.getpwuid(os.stat(path).st_uid).pw_name
    except (OSError, KeyError):
        return ""


def current_uid() -> int | None:
    """Numeric user ID for the current process, if available."""
    return os.getuid() if hasattr(os, "getuid") else None


def current_user() -> str:
    """Best-effort username for the current process."""
    uid = current_uid()
    if _pwd is not None and uid is not None:
        try:
            return _pwd.getpwuid(uid).pw_name
        except (KeyError, OSError):
            pass
    return os.environ.get("USER") or os.environ.get("LOGNAME") or os.environ.get("USERNAME") or ""


def get_tty() -> str:
    """Controlling tty device (POSIX only) or ''."""
    if not hasattr(os, "ttyname"):
        return ""
    try:
        return os.ttyname(sys.stdin.fileno())
    except OSError:
        return ""


def lax_perms(path: PathLike) -> bool:
    """True if *path* is group/world readable, writable or executable."""
    try:
        mode = stat.S_IMODE(os.stat(path).st_mode)
    except OSError:
        return False
    return bool(mode & (stat.S_IRWXG | stat.S_IRWXO))


def lax_perm_warning(keydir: PathLike) -> str:
    """Canonical warning text for a keychain dir / pidfile with lax perms.

    Single source of truth for both the runtime add-path warnings
    (:meth:`keychain.paths.KeychainPaths.ensure_keydir` /
    :meth:`check_pidfile_perms`) and the ``inspect`` action's post-panel
    audit warnings, so the wording can't drift between code paths.
    """
    return f"Keychain dir has lax permissions. Use chmod -R go-rwx '{keydir}' to fix."


def unlink_quiet(*paths: PathLike) -> None:
    for p in paths:
        with contextlib.suppress(OSError):
            os.unlink(p)


def dedupe_sorted(items: Iterable[str]) -> list[str]:
    """Deterministic deduplication: insertion-order de-dup, then sorted."""
    seen: set[str] = set()
    out: list[str] = []
    for it in items:
        if it and it not in seen:
            seen.add(it)
            out.append(it)
    out.sort()
    return out
