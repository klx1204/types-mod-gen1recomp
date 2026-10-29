#!/usr/bin/env bash
# Pack the mod from git, not from a hand-written file list: anything tracked
# ships unless .gitattributes says export-ignore, so a new data file cannot be
# forgotten.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VER="${1:-}"
if [ -z "$VER" ]; then
  echo "usage: scripts/pack.sh <version>   e.g. scripts/pack.sh 0.1.9" >&2
  exit 1
fi
printf '%s' "$VER" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$' || {
  echo "invalid version '$VER'" >&2
  exit 1
}

if [ -n "$(git status --porcelain)" ]; then
  echo "working tree is dirty; commit first so the archive matches the tag" >&2
  exit 1
fi

MANIFEST_VER="$(python3 -c "import json;print(json.load(open('manifest.json'))['version'])")"
if [ "$MANIFEST_VER" != "$VER" ]; then
  echo "manifest.json says $MANIFEST_VER, packing $VER" >&2
  exit 1
fi

luajit -e "assert(loadfile('main.lua'))"
if [ -f visible_wild.lua ]; then
  luajit -e "assert(loadfile('visible_wild.lua'))"
fi
luajit tests/main_smoke_test.lua
luajit tests/apply_test.lua

mkdir -p dist
OUT="dist/types_mod_gen1recomp-$VER.zip"
rm -f "$OUT"
git archive --format=zip --prefix=types_mod_gen1recomp/ -o "$OUT" HEAD

echo
unzip -l "$OUT"
echo
shasum -a 256 "$OUT"
