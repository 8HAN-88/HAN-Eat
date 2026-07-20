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
    # Deferred loading may place some strings in *.part.js — search all JS chunks.
    js_blobs = [main_js]
    for part in sorted(root.glob("main.dart.js_*.part.js")):
        js_blobs.append(part.read_text(encoding="utf-8", errors="ignore"))
    all_js = "\n".join(js_blobs)
    if build_number not in all_js:
        fail("WEB_BUILD_ID from version.json is not embedded in main.dart.js / parts")
    # Cold-start chunk must still carry the build id (auth shell + auto-update).
    if build_number not in main_js:
        fail(
            "WEB_BUILD_ID must be present in main.dart.js (cold-start chunk), "
            "not only in deferred parts"
        )
    if expected_api not in all_js:
        fail(f"HANEAT_API_BASE {expected_api!r} is not embedded in main.dart.js / parts")
    if expected_api not in main_js:
        fail(
            f"HANEAT_API_BASE {expected_api!r} must be present in main.dart.js "
            "(auth/API cold start)"
        )

    bootstrap = bootstrap_path.read_text(encoding="utf-8", errors="ignore")
    cfg_marker = "_flutter.buildConfig = "
    cfg_start = bootstrap.find(cfg_marker)
    if cfg_start < 0:
        fail("flutter_bootstrap.js missing _flutter.buildConfig")
    cfg_json = bootstrap[cfg_start + len(cfg_marker) :].split(";", 1)[0]
    cfg = json.loads(cfg_json)
    builds = cfg.get("builds") or []
    if any(
        isinstance(b, dict) and b.get("compileTarget") == "dart2wasm"
        for b in builds
    ):
        fail("wasm dual-build must not ship (Safari white-screen risk)")
    if not any(
        isinstance(b, dict) and b.get("compileTarget") == "dart2js"
        for b in builds
    ):
        fail("dart2js build missing from buildConfig")
    load_tail = bootstrap[bootstrap.rfind("_flutter.loader.load") :]
    if 'renderer: "canvaskit"' not in load_tail and 'renderer:"canvaskit"' not in load_tail:
        fail("flutter_bootstrap.js must force canvaskit renderer")
    if "serviceWorkerSettings" in load_tail:
        fail("flutter_bootstrap.js must not enable serviceWorkerSettings")
    if (root / "main.dart.wasm").exists():
        fail("main.dart.wasm must not be present in build/web")

    print(f"web build check passed: build={build_number}, api={expected_api}")


if __name__ == "__main__":
    main()
