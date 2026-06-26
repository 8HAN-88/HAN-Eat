#!/usr/bin/env python3
"""Validate web build artifacts before deploy."""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path


def fail(message: str) -> None:
    print(f"web build check failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def main() -> None:
    root = Path("build/web")
    version_path = root / "version.json"
    main_js_path = root / "main.dart.js"
    bootstrap_path = root / "flutter_bootstrap.js"

    for path in (version_path, main_js_path, bootstrap_path):
        if not path.is_file():
            fail(f"missing {path}")

    version = json.loads(version_path.read_text(encoding="utf-8"))
    build_number = str(version.get("build_number") or version.get("version") or "")
    if not build_number:
        fail("version.json has no build_number/version")

    expected_api = os.environ.get("HANEAT_API_BASE", "").strip()
    if not expected_api:
        fail("HANEAT_API_BASE env is required")

    main_js = main_js_path.read_text(encoding="utf-8", errors="ignore")
    if build_number not in main_js:
        fail("WEB_BUILD_ID from version.json is not embedded in main.dart.js")
    if expected_api not in main_js:
        fail(f"HANEAT_API_BASE {expected_api!r} is not embedded in main.dart.js")

    print(f"web build check passed: build={build_number}, api={expected_api}")


if __name__ == "__main__":
    main()
