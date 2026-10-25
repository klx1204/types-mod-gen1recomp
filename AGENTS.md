# AGENTS.md — types-mod-gen1recomp

## What this repo is

A gen1recomp **content mod** for the Gen 3 games (FireRed, LeafGreen, Emerald):

- an 18-type Gen 9 chart (adds Fairy and the Gen 6+ Steel resistances);
- Gen 9 types for the 18 Gen 3 species that gained Fairy;
- four existing move type changes (Charm, Moonlight, Sweet Kiss, Curse);
- optional per-move physical/special categories;
- a small set of Gen 9 Fairy moves and level-up learnsets;
- optional quality-of-life enhancements that are implemented entirely through
  public mod hooks.

This repository contains **no engine source**. It runs on top of gen1recomp via
the mod API.

## Hard rules

1. Never copy gen1recomp engine source into this repository.
2. Never hard-code a local absolute path (a home-directory path or a Windows drive path).
   Offline tools accept explicit arguments:
   - `--showdown <path>` or `SHOWDOWN_DIR`
   - `--cfru <path>` or `CFRU_DIR`
   - `ENGINE_DIR` for engine smoke tests
3. Tests must not require a local ROM, a Showdown checkout or a CFRU checkout.
   Use synthetic tables under `tests/fixtures/` or the committed `data/*.lua`.
4. Support both engines:
   - official `bryanthaboi/gen1recomp` → **compat mode**: types, species,
     moves, learnsets and enhancements work; per-move physical/special is
     unavailable and Play Rough falls back to the type-based category.
   - `klx1204/gen1recomp-ps-split` → **full mode**: per-move physical/special
     works and the battle move menu can show it.
5. Do not add Fairy TMs or HMs. The Gen 3 TM/HM list stays untouched.
6. Do not add new abilities.
7. A data-mode change is only allowed **outside battle**. In battle, refuse the
   change and leave the current mode untouched.
8. `affects_link` is `true`. Different data modes must not link with each other.
9. Do not commit ROMs, ROM-derived sprites, or CFRU/DPE artwork. The Fairy type
   icon is optional; public releases should use a self-drawn icon or the text
   fallback.

## Public URLs

- Engine: https://github.com/bryanthaboi/gen1recomp
- Engine fork: https://github.com/klx1204/gen1recomp-ps-split
- This repository: https://github.com/klx1204/types-mod-gen1recomp

## Layout

- `main.lua` — entry point: capability detection, mode switch, hooks.
- `data/` — static or generated Lua tables. No local paths.
- `tools/` — offline generators. Never executed by the game.
- `tests/` — headless checks. No ROM, Showdown or CFRU checkout required.
- `assets/` — optional mod-owned art with relative paths only.

## Mode semantics

- `VANILLA`: restore the captured baseline tables.
- `GEN9`: apply the Gen 9 type chart, species types, move type changes and,
  in full mode, per-move categories.
- If `data/types.lua` has `complete = false`, the mod stays in `VANILLA` and
  logs a warning. This prevents a half-generated chart from replacing the
  vanilla matchups.

## Engine compatibility detection

```lua
local Types = require("src.core.game3.battle.types")
local FULL = type(rawget(Types, "MOVE_CATEGORY")) == "boolean"
```

Never assume `MOVE_CATEGORY` exists. Strip or skip category data in compat mode.

## Commands

```bash
# data sanity
luajit tests/data_test.lua

# engine smoke test (optional; skips when ENGINE_DIR is unset)
ENGINE_DIR=/path/to/gen1recomp luajit tests/engine_smoke_test.lua

# offline generators
python3 tools/export_showdown.py --showdown /path/to/pokemon-showdown
python3 tools/extract_fairy_icon.py --cfru /path/to/Complete-Fire-Red-Upgrade

# path hygiene
git grep -n -I -E "/Users/[^/]+|C:\\\\Users|/home/[a-z]" -- . \
  ':!*.png' ':!*.rgba' ':!*.bin'
```

## Release checklist

- [ ] `data/types.lua` has `complete = true` and a full 18×18 matchup table.
- [ ] `tests/data_test.lua` passes.
- [ ] No local absolute paths.
- [ ] `manifest.json` still declares `affects_link: true`.
- [ ] README compatibility matrix matches the current engine state.
- [ ] No ROM, ROM-derived sprites or CFRU/DPE artwork are bundled.
