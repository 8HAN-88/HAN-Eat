#!/usr/bin/env python3
"""PWA-иконки из app_icon_source.png без дополнительных чёрных полей."""
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

# Только maskable: безопасная зона под круглую маску iOS/Android.
MASKABLE_PADDING = 0.10


def _render(src: Image.Image, size: int, padding_ratio: float = 0.0) -> Image.Image:
    if padding_ratio <= 0:
        return src.resize((size, size), Image.Resampling.LANCZOS).convert("RGB")

    canvas = Image.new("RGBA", (size, size), BG)
    pad = int(size * padding_ratio)
    inner = size - 2 * pad
    ratio = min(inner / src.width, inner / src.height)
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
        _render(src, size).save(OUT / name, "PNG")

    for size, name in ((192, "Icon-maskable-192.png"), (512, "Icon-maskable-512.png")):
        _render(src, size, padding_ratio=MASKABLE_PADDING).save(OUT / name, "PNG")

    _render(src, 32).save(ROOT / "web" / "favicon.png", "PNG")
    print(f"✓ PWA icons (no extra borders) → {OUT}")


if __name__ == "__main__":
    main()
