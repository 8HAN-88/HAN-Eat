#!/usr/bin/env python3
"""Keep Flutter's generated web_plugin_registrant.dart slim during build.

Flutter always regenerates a full registrant (video/WebView/Firebase/…).
That forces those packages into main.dart.js even when app code is deferred.
This watcher overwrites the registrant with the light template whenever the
tool writes the fat version, so dart2js compiles the slim entry.
"""
from __future__ import annotations

import argparse
import subprocess
import sys
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LIGHT = ROOT / "scripts" / "templates" / "web_plugin_registrant_light.dart"
BUILD_ROOT = ROOT / ".dart_tool" / "flutter_build"

HEAVY_MARKERS = (
    "InAppWebView",
    "VideoPlayerPlugin",
    "FirebaseMessagingWeb",
    "FirebaseFirestoreWeb",
    "audioplayers_web",
)


def is_fat(text: str) -> bool:
    return any(m in text for m in HEAVY_MARKERS)


def patch_once(light_text: str) -> int:
    if not BUILD_ROOT.is_dir():
        return 0
    n = 0
    for path in BUILD_ROOT.glob("*/web_plugin_registrant.dart"):
        try:
            current = path.read_text(encoding="utf-8")
        except OSError:
            continue
        if is_fat(current) or current != light_text:
            if is_fat(current) or "HAN-Eat cold start" not in current:
                path.write_text(light_text, encoding="utf-8")
                n += 1
    return n


def watch(stop: threading.Event, light_text: str) -> None:
    while not stop.is_set():
        patch_once(light_text)
        time.sleep(0.03)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    cmd = args.command
    if cmd and cmd[0] == "--":
        cmd = cmd[1:]
    if not cmd:
        print("usage: patch_web_plugin_registrant_during_build.py -- <flutter build...>", file=sys.stderr)
        return 2
    if not LIGHT.is_file():
        print(f"missing {LIGHT}", file=sys.stderr)
        return 2

    light_text = LIGHT.read_text(encoding="utf-8")
    stop = threading.Event()
    t = threading.Thread(target=watch, args=(stop, light_text), daemon=True)
    t.start()
    try:
        proc = subprocess.run(cmd, cwd=str(ROOT))
        # Final pass after build in case the last write raced the watcher.
        patched = patch_once(light_text)
        if patched:
            print(f"✓ slim web_plugin_registrant applied ({patched} file(s))")
        # Verify newest registrant is light (informational; JS already compiled).
        newest = None
        newest_mtime = -1.0
        if BUILD_ROOT.is_dir():
            for path in BUILD_ROOT.glob("*/web_plugin_registrant.dart"):
                m = path.stat().st_mtime
                if m > newest_mtime:
                    newest_mtime = m
                    newest = path
        if newest and is_fat(newest.read_text(encoding="utf-8")):
            print(
                "WARNING: web_plugin_registrant.dart still fat after build — "
                "main.dart.js may include heavy plugins",
                file=sys.stderr,
            )
        return proc.returncode
    finally:
        stop.set()
        t.join(timeout=1)


if __name__ == "__main__":
    raise SystemExit(main())
