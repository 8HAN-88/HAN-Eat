#!/usr/bin/env python3
"""PWA-иконки: чёрный фон, логотип на весь значок (как на домашнем экране)."""
from __future__ import annotations

import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("pip install Pillow", file=sys.stderr)
    sys.exit(1)

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "assets" / "app_icon_source.png"
OUT = ROOT / "web" / "icons"
BG = (0, 0, 0, 255)


def _fit_cover(src: Image.Image, size: int, padding_ratio: float = 0.0) -> Image.Image:
    canvas = Image.new("RGBA", (size, size), BG)
    pad = int(size * padding_ratio)
    inner = size - 2 * pad
    ratio = max(inner / src.width, inner / src.height)
    nw, nh = max(1, int(src.width * ratio)), max(1, int(src.height * ratio))
    resized = src.resize((nw, nh), Image.Resampling.LANCZOS)
    x, y = (size - nw) // 2, (size - nh) // 2
    canvas.paste(resized, (x, y), resized)
    return canvas.convert("RGB")


def main() -> None:
    if not SRC.is_file():
        print(f"Missing {SRC}", file=sys.stderr)
        sys.exit(1)
    OUT.mkdir(parents=True, exist_ok=True)
    src = Image.open(SRC).convert("RGBA")

    for size, name in (
        (180, "Icon-180.png"),
        (192, "Icon-192.png"),
        (512, "Icon-512.png"),
    ):
        _fit_cover(src, size, padding_ratio=0.02).save(OUT / name, "PNG")

    # Maskable: безопасная зона ~80% — чуть меньше логотип, тот же чёрный фон.
    for size, name in ((192, "Icon-maskable-192.png"), (512, "Icon-maskable-512.png")):
        _fit_cover(src, size, padding_ratio=0.10).save(OUT / name, "PNG")

    favicon = _fit_cover(src, 32, padding_ratio=0.04)
    favicon.save(ROOT / "web" / "favicon.png", "PNG")
    print(f"✓ PWA icons (black bg) → {OUT}")


if __name__ == "__main__":
    main()
