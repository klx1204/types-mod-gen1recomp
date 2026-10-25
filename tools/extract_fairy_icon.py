#!/usr/bin/env python3
"""Extract the CFRU Fairy type icon (32x16) from Type_Icons.bmp.

Usage:
    python3 tools/extract_fairy_icon.py --cfru /path/to/Complete-Fire-Red-Upgrade
    CFRU_DIR=/path/to/Complete-Fire-Red-Upgrade python3 tools/extract_fairy_icon.py

The CFRU sheet is 128x144 with 4 columns x 9 rows of 32x16 cells. CFRU's
TYPE_FAIRY is 0x17 (23), so cell 23 is the Fairy icon.

This tool is optional. The mod works without the icon (text fallback).
Requires Pillow: python3 -m pip install pillow
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

CELL_W, CELL_H = 32, 16
COLUMNS = 4
FAIRY_INDEX = 0x17  # CFRU include/constants/pokemon.h: TYPE_FAIRY


def fail(message: str) -> "None":
    print(f"extract_fairy_icon: {message}", file=sys.stderr)
    raise SystemExit(2)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cfru", default=os.environ.get("CFRU_DIR"),
                        help="path to a Complete-Fire-Red-Upgrade checkout")
    parser.add_argument("--out", default="assets/type_icons/fairy.png",
                        help="output PNG (default: assets/type_icons/fairy.png)")
    args = parser.parse_args()

    if not args.cfru:
        fail("pass --cfru <path> or set CFRU_DIR")
    root = Path(args.cfru).expanduser().resolve()
    sheet = root / "graphics" / "Other" / "Type_Icons" / "Type_Icons.bmp"
    if not sheet.is_file():
        fail(f"missing {sheet}")

    try:
        from PIL import Image
    except ImportError:
        fail("Pillow is required: python3 -m pip install pillow")

    image = Image.open(sheet).convert("RGBA")
    if image.size != (128, 144):
        fail(f"expected a 128x144 sheet, got {image.size[0]}x{image.size[1]}")

    col = FAIRY_INDEX % COLUMNS
    row = FAIRY_INDEX // COLUMNS
    left, top = col * CELL_W, row * CELL_H
    icon = image.crop((left, top, left + CELL_W, top + CELL_H))

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    icon.save(out)
    print(f"wrote {out} ({CELL_W}x{CELL_H}) from cell {FAIRY_INDEX}")


if __name__ == "__main__":
    main()
