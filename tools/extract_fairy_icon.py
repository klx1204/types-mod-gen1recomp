#!/usr/bin/env python3
"""Extract the CFRU Fairy type icon (32x16) from Type_Icons.bmp.

Usage:
    python3 tools/extract_fairy_icon.py --cfru /path/to/Complete-Fire-Red-Upgrade
    CFRU_DIR=/path/to/Complete-Fire-Red-Upgrade python3 tools/extract_fairy_icon.py

The CFRU sheet is 128x144 with 4 columns x 9 rows of 32x16 cells.  The
type icons are not in numeric order: FAIRY sits alone on the last row, in
column 0 (cell 32), not at TYPE_FAIRY's numeric 0x17.

This tool is optional. The mod works without the icon (text fallback).
Requires Pillow: python3 -m pip install pillow
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

CELL_W, ICON_H = 32, 12
SLOT_H = 16
PAD_TOP = 2
HIGHLIGHT_ROW, SHADOW_ROW = 1, 14
HIGHLIGHT = (255, 224, 255, 255)
SHADOW = (174, 108, 174, 255)
COLUMNS = 4
# The sheet groups NORMAL/FIRE/WATER/GRASS first; FAIRY is the lone badge on
# the last row.  Verified against Type_Icons.bmp: row 8, column 0.
FAIRY_COL, FAIRY_ROW = 0, 8


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
        from PIL import Image, ImageDraw
    except ImportError:
        fail("Pillow is required: python3 -m pip install pillow")

    image = Image.open(sheet).convert("RGBA")
    if image.size != (128, 144):
        fail(f"expected a 128x144 sheet, got {image.size[0]}x{image.size[1]}")

    # The sheet's cells are 32x16 but the badge art occupies the top 12 rows;
    # the bottom four rows are the sheet background.  Emerald's own badges are
    # a 1px highlight row, a 12px body and a 1px shadow row, so rebuild that
    # shape instead of pasting the flat CFRU block.
    left, top = FAIRY_COL * CELL_W, FAIRY_ROW * 16
    icon = image.crop((left, top, left + CELL_W, top + ICON_H))
    canvas = Image.new("RGBA", (CELL_W, SLOT_H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    draw.rectangle((0, HIGHLIGHT_ROW, CELL_W - 1, HIGHLIGHT_ROW), fill=HIGHLIGHT)
    draw.rectangle((0, SHADOW_ROW, CELL_W - 1, SHADOW_ROW), fill=SHADOW)
    canvas.paste(icon, (0, PAD_TOP))
    # 1px corner cuts, matching the native badges (WATER/FIRE/GRASS).
    for x, y in ((0, HIGHLIGHT_ROW), (CELL_W - 1, HIGHLIGHT_ROW),
                 (0, SHADOW_ROW), (CELL_W - 1, SHADOW_ROW)):
        canvas.putpixel((x, y), (0, 0, 0, 0))
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out)
    print(f"wrote {out} ({CELL_W}x{SLOT_H}) from row {FAIRY_ROW}, column {FAIRY_COL}")


if __name__ == "__main__":
    main()
