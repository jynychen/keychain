# SPDX-License-Identifier: GPL-3.0-only
"""Tests for the thin PEP 517 backend wrapper."""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from types import ModuleType, SimpleNamespace

import pytest


def _load_backend(monkeypatch, build_meta):
    fake_setuptools = ModuleType("setuptools")
    fake_setuptools.build_meta = build_meta
    monkeypatch.setitem(sys.modules, "setuptools", fake_setuptools)

    spec = importlib.util.spec_from_file_location(
        "build_backend_testcopy",
        Path(__file__).resolve().parents[1] / "scripts" / "build_backend.py",
    )
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_editable_hooks_fail_clearly_when_setuptools_lacks_pep660(monkeypatch):
    backend = _load_backend(monkeypatch, SimpleNamespace())
    monkeypatch.setattr(backend, "_generate_docs", lambda: None)
    monkeypatch.setattr(backend, "_setuptools", SimpleNamespace())

    with pytest.raises(SystemExit, match="setuptools>=64"):
        backend.get_requires_for_build_editable(None)

    with pytest.raises(SystemExit, match="setuptools>=64"):
        backend.prepare_metadata_for_build_editable("meta")

    with pytest.raises(SystemExit, match="setuptools>=64"):
        backend.build_editable("dist")


def test_pyproject_declares_main_entrypoint_and_docs_package():
    text = (Path(__file__).resolve().parents[1] / "pyproject.toml").read_text(encoding="utf-8")

    assert 'keychain = "keychain.main:main"' in text
    assert 'build-backend = "build_backend"' in text
    assert 'backend-path = ["scripts"]' in text
    assert '"keychain.docs"' in text
