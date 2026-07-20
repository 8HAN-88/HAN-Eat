#!/usr/bin/env python3
"""Recompile Flutter web JS after forcing a light web_plugin_registrant.dart.

Flutter regenerates a fat registrant on every build. The mid-build watcher is
best-effort; this step makes the slim cold-start chunk reliable by re-running
dart2js against the already-generated entrypoint with the light registrant.
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LIGHT = ROOT / "scripts" / "templates" / "web_plugin_registrant_light.dart"
BUILD_WEB = ROOT / "build" / "web"
FLUTTER_ROOT = Path(os.environ.get("FLUTTER_ROOT", Path.home() / "flutter"))
if not (FLUTTER_ROOT / "bin" / "flutter").exists():
    # Resolve via `which flutter`
    which = shutil.which("flutter")
    if which:
        FLUTTER_ROOT = Path(which).resolve().parent.parent

DART = FLUTTER_ROOT / "bin" / "cache" / "dart-sdk" / "bin" / "dart"
PLATFORM = FLUTTER_ROOT / "bin" / "cache" / "flutter_web_sdk" / "kernel"


def newest_build_dir() -> Path:
    root = ROOT / ".dart_tool" / "flutter_build"
    candidates = [
        p for p in root.iterdir() if (p / "main.dart").is_file() and (p / "web_plugin_registrant.dart").is_file()
    ]
    if not candidates:
        raise SystemExit("no flutter_build dir with main.dart — run flutter build web first")
    return max(candidates, key=lambda p: (p / "main.dart").stat().st_mtime)


def dart_defines_from_env_and_build_id(build_id: str) -> list[str]:
    defines = [
        f"-DWEB_BUILD_ID={build_id}",
        "-Ddart.vm.product=true",
        "-DFLUTTER_WEB_USE_SKIA=true",
    ]
    # Reuse the same helper the release script uses.
    proc = subprocess.run(
        [str(ROOT / "scripts" / "load_dart_defines.sh")],
        cwd=str(ROOT),
        capture_output=True,
        text=True,
        check=False,
    )
    for line in (proc.stdout or "").splitlines():
        line = line.strip()
        if line.startswith("--dart-define="):
            defines.append("-D" + line[len("--dart-define=") :])
    # Ensure API base present even if helper only echoes flutter flags.
    api = os.environ.get("HANEAT_API_BASE", "https://api.haneat.app")
    if not any(d.startswith("-DHANEAT_API_BASE=") for d in defines):
        defines.append(f"-DHANEAT_API_BASE={api}")
    variant = os.environ.get("APP_VARIANT", "social")
    if not any(d.startswith("-DAPP_VARIANT=") for d in defines):
        defines.append(f"-DAPP_VARIANT={variant}")
    # Prefer local CanvasKit (build uses --no-web-resources-cdn).
    if not any(d.startswith("-DFLUTTER_WEB_CANVASKIT_URL=") for d in defines):
        defines.append("-DFLUTTER_WEB_CANVASKIT_URL=canvaskit/")
    return defines


def main() -> int:
    if not LIGHT.is_file():
        print(f"missing {LIGHT}", file=sys.stderr)
        return 2
    if not DART.is_file():
        print(f"missing dart at {DART}", file=sys.stderr)
        return 2
    if not PLATFORM.is_dir():
        print(f"missing platform kernels at {PLATFORM}", file=sys.stderr)
        return 2

    build_dir = newest_build_dir()
    print(f"recompile slim plugins in {build_dir}")
    (build_dir / "web_plugin_registrant.dart").write_text(
        LIGHT.read_text(encoding="utf-8"), encoding="utf-8"
    )

    # Read BUILD_ID from existing version.json if present.
    build_id = os.environ.get("WEB_BUILD_ID", "")
    version_path = BUILD_WEB / "version.json"
    if not build_id and version_path.is_file():
        import json

        build_id = str(json.loads(version_path.read_text(encoding="utf-8")).get("build_number", ""))
    if not build_id:
        from datetime import datetime, timezone

        build_id = datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S")

    packages = ROOT / ".dart_tool" / "package_config.json"
    defines = dart_defines_from_env_and_build_id(build_id)
    shared = [
        str(DART),
        "compile",
        "js",
        f"--platform-binaries={PLATFORM}",
        "--invoker=flutter_tool",
        "--no-source-maps",
        "-O4",
        "--minify",
        *defines,
    ]
    app_dill = build_dir / "app.dill"
    main_dart = build_dir / "main.dart"
    out_js = build_dir / "main.dart.js"

    print("→ dart2js CFE")
    subprocess.run(
        [
            *shared,
            "-o",
            str(app_dill),
            f"--packages={packages}",
            "--cfe-only",
            str(main_dart),
        ],
        cwd=str(ROOT),
        check=True,
    )
    print("→ dart2js emit")
    subprocess.run(
        [*shared, "-o", str(out_js), str(app_dill)],
        cwd=str(ROOT),
        check=True,
    )

    # Replace JS bundles in build/web (drop stale part files from prior compiles).
    BUILD_WEB.mkdir(parents=True, exist_ok=True)
    for stale in BUILD_WEB.glob("main.dart.js*"):
        stale.unlink()
    for src in sorted(build_dir.glob("main.dart.js*")):
        if src.name.endswith(".map") or src.name.endswith(".deps"):
            continue
        dest = BUILD_WEB / src.name
        shutil.copy2(src, dest)
        print(f"✓ {dest.relative_to(ROOT)} ({src.stat().st_size / 1e6:.2f} MB)")

    main_size = (BUILD_WEB / "main.dart.js").stat().st_size
    print(f"main.dart.js = {main_size / 1e6:.2f} MB")
    text = (BUILD_WEB / "main.dart.js").read_text(encoding="utf-8", errors="ignore")
    for marker in ("InAppWebViewFlutterPlugin", "VideoPlayerPlugin.registerWith", "FirebaseMessagingWeb"):
        if marker in text:
            print(f"WARNING: {marker} still present in main.dart.js", file=sys.stderr)
        else:
            print(f"✓ main chunk free of {marker}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
