# SPDX-License-Identifier: GPL-3.0-only
"""Tests for keychain.help: JSON renderers and double-blank-line fix."""

import io
import sys
from contextlib import contextmanager

import pytest

from keychain.main import helpinfo
from keychain.paths import KeychainPaths
from keychain.state import KeychainState


@contextmanager
def _capture_stdout():
    buf = io.StringIO()
    old = sys.stdout
    sys.stdout = buf
    try:
        yield buf
    finally:
        sys.stdout = old


@pytest.fixture
def state(tmp_path):
    keydir = tmp_path / ".keychain"
    keydir.mkdir(mode=0o700)
    return KeychainState(paths=KeychainPaths(keydir=keydir, host="testhost"))


def test_helpinfo_no_double_blank_between_gpl_and_actions():
    """Regression: helpinfo() must not lead with a double blank line so the
    Actions header sits cleanly under whatever caller printed before it."""
    with _capture_stdout() as buf_out:
        # versinfo writes to stderr; helpinfo writes to stdout.
        helpinfo()
    text = buf_out.getvalue()
    # No double-blank-line at the start.
    assert not text.startswith("\n\n")
    # Actions header is the first non-empty line.
    assert text.lstrip().startswith("Actions")
