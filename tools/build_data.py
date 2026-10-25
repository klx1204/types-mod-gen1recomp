#!/usr/bin/env python3
"""Validate the committed mod scaffold without a ROM or engine checkout."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REQUIRED = [
    "manifest.json",
    "main.lua",
    "data/types.lua",
    "data/species_fairy.lua",
    "data/move_types_changed.lua",
    "data/move_categories.lua",
    "data/moves_fairy.lua",
    "data/learnsets_fairy.lua",
]

# A real local path, not a /path/to placeholder in documentation.
_USER_PREFIX = "/Users/"
LOCAL_PATH = re.compile(_USER_PREFIX + r"[^/]+/Downloads|C:\\\\Users\\\\|/home/[a-z]+/")

# The checker itself contains the pattern; it is not a local reference.
SKIP = {
    (ROOT / "tools" / "build_data.py").resolve(),
    (ROOT / ".github" / "workflows" / "ci.yml").resolve(),
    (ROOT / "docs" / "ci.yml.pending").resolve(),
}


def fail(message: str) -> "None":
    print(f"build_data: {message}", file=sys.stderr)
    raise SystemExit(1)


def main() -> None:
    for rel in REQUIRED:
        if not (ROOT / rel).is_file():
            fail(f"missing {rel}")

    manifest = json.loads((ROOT / "manifest.json").read_text(encoding="utf-8"))
    for key in ("id", "name", "version", "api", "entry", "games"):
        if key not in manifest:
            fail(f"manifest.json is missing {key}")
    if manifest["api"] != 3:
        fail("manifest api must be 3")
    if manifest.get("affects_link") is not True:
        fail("affects_link must be true")

    for path in ROOT.rglob("*"):
        if path.is_dir() or ".git" in path.parts:
            continue
        if path.resolve() in SKIP:
            continue
        if path.suffix.lower() in {".png", ".rgba", ".bin"}:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        for line_no, line in enumerate(text.splitlines(), 1):
            if LOCAL_PATH.search(line):
                fail(f"local path at {path.relative_to(ROOT)}:{line_no}: {line.strip()}")

    print("build_data: ok")


if __name__ == "__main__":
    main()
