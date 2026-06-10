# SPDX-License-Identifier: GPL-3.0-only
from __future__ import annotations

import subprocess
import sys
from pathlib import Path
from typing import Any

from setuptools import build_meta as _setuptools

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "build_doc_texts.py"
OUTPUT = ROOT / "src" / "keychain" / "docs" / "_doc_texts.json"


def _generate_docs() -> None:
    if SCRIPT.is_file():
        subprocess.run([sys.executable, str(SCRIPT)], check=True)
    elif not OUTPUT.is_file():
        raise SystemExit("missing generated docs JSON")


def _editable_hook(name: str):
    hook = getattr(_setuptools, name, None)
    if hook is None:
        raise SystemExit("editable builds require setuptools>=64")
    return hook


def get_requires_for_build_wheel(config_settings: dict[str, Any] | None = None) -> list[str]:
    return _setuptools.get_requires_for_build_wheel(config_settings)


def prepare_metadata_for_build_wheel(metadata_directory: str, config_settings: dict[str, Any] | None = None) -> str:
    _generate_docs()
    return _setuptools.prepare_metadata_for_build_wheel(metadata_directory, config_settings)


def build_wheel(
    wheel_directory: str,
    config_settings: dict[str, Any] | None = None,
    metadata_directory: str | None = None,
) -> str:
    _generate_docs()
    return _setuptools.build_wheel(wheel_directory, config_settings, metadata_directory)


def build_sdist(sdist_directory: str, config_settings: dict[str, Any] | None = None) -> str:
    _generate_docs()
    return _setuptools.build_sdist(sdist_directory, config_settings)


def get_requires_for_build_editable(config_settings: dict[str, Any] | None = None) -> list[str]:
    return _editable_hook("get_requires_for_build_editable")(config_settings)


def prepare_metadata_for_build_editable(metadata_directory: str, config_settings: dict[str, Any] | None = None) -> str:
    _generate_docs()
    return _editable_hook("prepare_metadata_for_build_editable")(metadata_directory, config_settings)


def build_editable(
    wheel_directory: str,
    config_settings: dict[str, Any] | None = None,
    metadata_directory: str | None = None,
) -> str:
    _generate_docs()
    return _editable_hook("build_editable")(wheel_directory, config_settings, metadata_directory)
