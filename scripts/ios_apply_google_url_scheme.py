#!/usr/bin/env python3
"""
Добавляет REVERSED_CLIENT_ID из GoogleService-Info.plist в ios/Runner/Info.plist.
Запуск: python3 scripts/ios_apply_google_url_scheme.py
"""
from __future__ import annotations

import plistlib
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GS_PLIST = ROOT / "ios/Runner/GoogleService-Info.plist"
INFO_PLIST = ROOT / "ios/Runner/Info.plist"


def main() -> int:
    if not GS_PLIST.is_file():
        print(f"FAIL: нет {GS_PLIST}")
        return 1

    with GS_PLIST.open("rb") as f:
        gs = plistlib.load(f)
    reversed_id = gs.get("REVERSED_CLIENT_ID")
    if not reversed_id:
        print("FAIL: REVERSED_CLIENT_ID не найден в GoogleService-Info.plist")
        return 1

    with INFO_PLIST.open("rb") as f:
        info = plistlib.load(f)

    url_types = info.setdefault("CFBundleURLTypes", [])
    if not url_types:
        url_types.append(
            {"CFBundleURLName": "Google Sign-In", "CFBundleURLSchemes": []}
        )

    # Первый dict с CFBundleURLSchemes или создать
    target = None
    for entry in url_types:
        if "CFBundleURLSchemes" in entry:
            target = entry
            break
    if target is None:
        target = {"CFBundleURLName": "Google Sign-In", "CFBundleURLSchemes": []}
        url_types.append(target)

    schemes = list(target.setdefault("CFBundleURLSchemes", []))
    if reversed_id in schemes:
        print(f"OK: scheme уже есть: {reversed_id}")
        return 0

    schemes.append(reversed_id)
    target["CFBundleURLSchemes"] = schemes

    with INFO_PLIST.open("wb") as f:
        plistlib.dump(info, f)

    print(f"OK: добавлен CFBundleURLSchemes → {reversed_id}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
