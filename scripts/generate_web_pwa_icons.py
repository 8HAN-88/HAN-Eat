#!/usr/bin/env python3
"""PWA-иконки: исходный файл как есть, только ресайз под нужные размеры."""
from __future__ import annotations

import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("pip install Pillow", file=sys.stderr)
    sys.exit(1)

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "assets" / "app_icon_raw.png"
OUT = ROOT / "web" / "icons"


def _resize(src: Image.Image, size: int) -> Image.Image:
    return src.resize((size, size), Image.Resampling.LANCZOS).convert("RGB")


def main() -> None:
    if not SRC.is_file():
        print(f"Missing {SRC}", file=sys.stderr)
        sys.exit(1)
    OUT.mkdir(parents=True, exist_ok=True)
    src = Image.open(SRC).convert("RGB")

    for size, name in (
        (180, "Icon-180.png"),
        (192, "Icon-192.png"),
        (512, "Icon-512.png"),
        (192, "Icon-maskable-192.png"),
        (512, "Icon-maskable-512.png"),
    ):
        _resize(src, size).save(OUT / name, "PNG")

    _resize(src, 32).save(ROOT / "web" / "favicon.png", "PNG")
    print(f"✓ PWA icons (raw, no crop/padding) → {OUT}")


if __name__ == "__main__":
    main()
