from __future__ import annotations

import os
from pathlib import Path


def set_home(monkeypatch, home: Path, *, patch_path_home: bool = False) -> None:
    """Point test home resolution at *home* across POSIX and Windows code paths."""
    if patch_path_home:
        monkeypatch.setattr(Path, "home", classmethod(lambda cls: home))
    monkeypatch.setenv("HOME", str(home))
    if os.name == "nt":
        monkeypatch.setenv("USERPROFILE", str(home))
        monkeypatch.delenv("HOMEDRIVE", raising=False)
        monkeypatch.delenv("HOMEPATH", raising=False)
