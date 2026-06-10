from __future__ import annotations

import subprocess
import sys
from pathlib import Path


def pytest_configure() -> None:
    root = Path(__file__).resolve().parents[1]
    subprocess.run([sys.executable, str(root / "scripts" / "build_doc_texts.py")], check=True)
