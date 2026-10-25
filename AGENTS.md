# AGENTS.md — types-mod-gen1recomp

## What this repo is

A gen1recomp **content mod** for the Gen 3 games (FireRed, LeafGreen, Emerald, Ruby, Sapphire):

- an 18-type Gen 9 chart (adds Fairy and the Gen 6+ Steel resistances);
- Gen 9 types for the 18 Gen 3 species that gained Fairy;
- four existing move type changes (Charm, Moonlight, Sweet Kiss, Curse);
- optional per-move physical/special categories for all 354 Gen 3 moves;
- 18 Gen 9 Fairy moves and Gen 9 level-up additions for 40 Gen 3 species;
- optional quality-of-life enhancements; the implemented ones use only public
  mod hooks, and the rest are marked planned.

This repository contains **no engine source**. It runs on top of gen1recomp via
the mod API.

## Current state

Present today:

- `data/types.lua` — complete 18-type Gen 9 chart, 324 matchups;
- `data/species_fairy.lua` — the 18 Fairy species;
- `data/move_types_changed.lua` — Charm, Moonlight, Sweet Kiss, Curse;
- `data/move_categories.lua` — 372 categories;
- `data/moves_fairy.lua` — 18 Fairy moves;
- `data/learnsets_fairy.lua` — 40 Gen 3 species with Gen 9 level-up Fairy moves;
- `main.lua` — GEN9/VANILLA switch, non-battle guard, four working hooks;
- `tests/data_test.lua`, `tests/main_smoke_test.lua`, `tests/apply_test.lua`,
  engine smoke test.

Planned, not implemented:

- Trade evolution at level 40;
- IV/EV viewer;
- an `ENHANCEMENTS` submenu (the rows currently sit at the bottom of OPTIONS).

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
   - `klx1204/gen1recomp-ps-split` → **full mode** when the fork exposes
     `Types.MOVE_CATEGORY`: per-move physical/special works and the battle move
     menu shows it. Older forks without the marker stay in compat mode.
5. Do not add Fairy TMs or HMs. The Gen 3 TM/HM list stays untouched.
6. Do not add new abilities.
7. `data/moves_fairy.lua` must never contain `category`. The official engine's
   `UnifiedContent` rejects it. Put per-move categories in
   `data/move_categories.lua`; `main.lua` applies them at runtime.
8. A data-mode change is only allowed **outside battle**. In battle, refuse the
   change and leave the current mode untouched.
9. `affects_link` is `true`. Different data modes must not link with each other.
10. Do not commit ROMs, ROM-derived sprites, or CFRU/DPE artwork. The Fairy type
    icon is optional; public releases should use a self-drawn icon or the text
    fallback.
11. This mod owns the Gen 9 type overlay and the 18 species while `GEN9` is
    active. Do not combine it with another mod that replaces `Types` or
    `Pokemon._types`; document the conflict instead.
12. `data.pokemon` is not rewritten. The runtime tables (`Pokemon._types`,
    `Pokemon._learnsets`, `Moves._rom`, `Pokemon._battleMoves`) are the source
    of truth while `GEN9` is active. Do not write `data.moves.category`: that
    field is contest data, not physical/special.
13. Skipped Fairy moves with no Gen 3 engine support: Misty Terrain, Fairy
    Lock, Flower Shield, Aromatic Mist, Crafty Shield, Geomancy, Decorate,
    Tera Blast. Draining Kiss uses the Gen 3 50% drain effect. Secondary
    effects use Gen 3 effect IDs; Alluring Voice's conditional and Sparkly
    Swirl's team-heal special cases are not modeled.
14. `data/moves_fairy.lua` stores effect **names** (`"ATTACK_DOWN_SIDE_EFFECT"`),
    never numbers. Engine-side tests pin the round-trip; a name the engine
    cannot map is refused silently and the move disappears.
15. Register the FAIRY type and the full chart in `mod.content.type_chart`
    before registering moves. The engine's move writer validates `type`
    against that registry, so a move with `type = "FAIRY"` is rejected when
    only the runtime overlay knows about Fairy. Keep the overlay for the
    instant `GEN 9` / `VANILLA` switch.
16. Also set `Types.CUSTOM_NAMES[18] = "FAIRY"` when the engine exposes it.
    The overlay is cleared on a VANILLA switch and may be rebuilt during a
    link battle, while `Pokemon._types` keeps 18 for a saved Pokémon. Without
    the persistent name, Emerald reads past the end of `gTypeNames` and shows
    the first contest category ("COOL") as the second type.
17. Set `Types.CUSTOM_ICONS[18]` to the bundled 32x16 badge when the engine
    exposes it. The summary screen indexes the ROM icon sheet by type id and
    frame 18 is COOL, so the icon has to come from `assets/type_icons` or the
    screen falls back to the type name.

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
  vanilla matchups. The committed chart is `complete = true`; the guard remains
  for future regenerations.

## Engine compatibility detection

```lua
local Types = require("src.core.game3.battle.types")
local FULL = type(rawget(Types, "MOVE_CATEGORY")) == "boolean"
```

Never assume `MOVE_CATEGORY` exists. Strip or skip category data in compat mode.

## Commands

```bash
# data and entry-point sanity
luajit tests/data_test.lua
luajit tests/main_smoke_test.lua
luajit tests/apply_test.lua

# engine smoke test (optional; skips when ENGINE_DIR is unset)
ENGINE_DIR=/path/to/gen1recomp luajit tests/engine_smoke_test.lua

# offline generators
python3 tools/export_showdown.py --showdown /path/to/pokemon-showdown
python3 tools/extract_fairy_icon.py --cfru /path/to/Complete-Fire-Red-Upgrade

# path hygiene: run your own check for local home-directory paths before commit
```

## Release checklist

- [ ] `data/types.lua` has `complete = true` and a full 18×18 matchup table.
- [ ] `tests/data_test.lua` passes.
- [ ] `tests/main_smoke_test.lua` passes.
- [ ] No local absolute paths.
- [ ] `manifest.json` still declares `affects_link: true`.
- [ ] README compatibility matrix matches the current engine state.
- [ ] No ROM, ROM-derived sprites or CFRU/DPE artwork are bundled.
