#!/usr/bin/env python3
"""Build psycopg2 Lambda layer zip for Python 3.13 (Linux x86_64)."""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
BUILD_DIR = SCRIPT_DIR / "build"
ZIP_FILE = SCRIPT_DIR / "psycopg2-layer.zip"
SITE_PACKAGES = BUILD_DIR / "python" / "lib" / "python3.13" / "site-packages"
REQUIREMENTS = SCRIPT_DIR / "requirements.txt"


def main() -> None:
    if BUILD_DIR.exists():
        shutil.rmtree(BUILD_DIR)
    if ZIP_FILE.exists():
        ZIP_FILE.unlink()

    SITE_PACKAGES.mkdir(parents=True, exist_ok=True)

    subprocess.run(
        [
            sys.executable,
            "-m",
            "pip",
            "install",
            "-r",
            str(REQUIREMENTS),
            "-t",
            str(SITE_PACKAGES),
            "--platform",
            "manylinux2014_x86_64",
            "--implementation",
            "cp",
            "--python-version",
            "3.13",
            "--only-binary=:all:",
        ],
        check=True,
    )

    shutil.make_archive(str(ZIP_FILE.with_suffix("")), "zip", BUILD_DIR)
    print(f"Created {ZIP_FILE}")


if __name__ == "__main__":
    main()
