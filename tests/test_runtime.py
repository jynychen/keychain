# SPDX-License-Identifier: GPL-3.0-only
"""Tests for :mod:`keychain.runtime` platform detection."""

import re

import pytest

from keychain.runtime import platform


@pytest.fixture(autouse=True)
def _reset_runtime():
    platform.reset()
    yield
    platform.reset()


@pytest.mark.parametrize("name", ["linux", "linux2", "darwin", "freebsd14", "openbsd7", "netbsd", "sunos5", "aix"])
def test_posix_platforms_supported(name):
    p = platform.detect(platform_override=name, has_ps=True)
    assert p.supported is True
    assert p.reason == ""


@pytest.mark.parametrize("name", ["cygwin", "msys", "msys2"])
def test_cygwin_msys_supported(name):
    p = platform.detect(platform_override=name, has_ps=True)
    assert p.supported is True


def test_native_windows_unsupported():
    p = platform.detect(platform_override="win32")
    assert p.supported is False
    assert p.name == "windows"
    assert "WSL" in p.reason or "Cygwin" in p.reason


def test_known_posix_ps_missing():
    # A known POSIX platform without ps in PATH is unsupported with a clear message.
    p = platform.detect(platform_override="linux", has_ps=False)
    assert p.supported is False
    assert "ps" in p.reason.lower()


def test_unknown_platform_with_ps():
    # An unrecognised platform string is accepted when ps is present.
    p = platform.detect(platform_override="plan9", has_ps=True)
    assert p.supported is True


def test_unknown_platform_without_ps():
    # An unrecognised platform without ps gets an "unrecognized" refusal.
    p = platform.detect(platform_override="plan9", has_ps=False)
    assert p.supported is False
    assert "unrecognized" in p.reason.lower()


def test_detection_is_cached():
    first = platform.detect(platform_override="linux", has_ps=True)
    second = platform.detect(platform_override="win32")  # ignored: cached
    assert first is second


def test_unsupported_process_list_raises():
    p = platform.detect(platform_override="win32")
    with pytest.raises(RuntimeError):
        p.process_list(re.compile("anything"))


def test_supported_process_list_returns_list():
    # Use the host's actual ``ps`` if available; otherwise the Popen call
    # raises OSError and the method returns an empty list.
    p = platform.detect()
    if not p.supported:
        pytest.skip("host platform unsupported")
    result = p.process_list(re.compile("definitely-not-a-real-command"))
    assert isinstance(result, list)
