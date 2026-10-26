# Gen 9 Types & Battle Data for gen1recomp

[中文](README.zh-CN.md)

A content mod for **gen1recomp** that brings a Gen 9 data layer to the Gen 3
games (FireRed, LeafGreen, Emerald, Ruby, Sapphire) without replacing the engine.

## What it does

- Adds the **Fairy** type and the Gen 6+ 18-type chart.
- Reassigns the 18 Gen 3 species that gained Fairy in later generations.
- Changes four existing moves to their modern types:
  - Charm: Normal → Fairy
  - Moonlight: Normal → Fairy
  - Sweet Kiss: Normal → Fairy
  - Curse: ??? → Ghost
- Provides per-move physical/special categories when the engine supports them
  (all 354 Gen 3 moves plus the new Fairy moves).
- Adds 18 Gen 9 Fairy moves with Gen 3-safe effects.
- Adds Gen 9 level-up Fairy moves to 40 Gen 3 species.
- Optional enhancements implemented through public hooks:
  - EXP for catching
  - Party EXP Share
  - Trade evolution at level 40 (planned)
  - HMs without knowing the move
  - Infinite TMs
  - IV/EV viewer (planned)

It does **not** add new abilities, Fairy TMs/HMs, visible wild Pokémon,
day/night, followers, or 3DS-specific features.

## Compatibility

| Engine | Gen 9 types/species/moves | Per-move physical/special | Battle menu category/effectiveness |
| --- | --- | --- | --- |
| Official gen1recomp | Yes | No (type-based fallback) | No |
| `gen1recomp-ps-split` | Yes | Yes (when the fork sets `Types.MOVE_CATEGORY`) | Yes (same condition) |

The mod detects the engine capability at load time. On the official engine it
runs in **compat mode** and logs a warning: Play Rough is treated as a special
move because the engine has no per-move category yet.

## Install

1. Install a gen1recomp build.
2. Copy this folder into the game's `mods/` directory as
   `mods/types_mod_gen1recomp/`.
3. Enable **Gen 9 Types & Battle Data** in the mod manager.
4. Open **OPTIONS** and scroll to the rows appended at the bottom:
   - `BATTLE DATA`: `GEN 9` / `VANILLA`
   - individual enhancement toggles

There is no separate `ENHANCEMENTS` page yet: the rows are added to the
top-level OPTIONS list.

The data mode can only be changed outside battle. In battle the option refuses
the change and keeps the current mode.

## Save and link notes

- `GEN 9` / `VANILLA` is stored in the mod's save bucket.
- Turning the mod off lets vanilla gen1recomp load the save, but it removes
  custom moves from Pokémon that know them (and falls back to TACKLE when all
  four slots are custom).
- `affects_link` is true: both peers need the same mod and data mode.
- The species-level Gen 9 learnsets apply to FireRed, LeafGreen, Emerald, Ruby
  and Sapphire. Per-version tutor and TM differences are not modeled.

## Current data state

Generated from Showdown and committed:

- `data/types.lua` — 18-type chart, 324 matchups;
- `data/species_fairy.lua` — the 18 Gen 3 species that gained Fairy; every
  other Gen 3 species keeps its Gen 3 types, which are identical to Gen 9;
- `data/move_types_changed.lua` — Charm, Moonlight, Sweet Kiss, Curse;
- `data/move_categories.lua` — 372 categories (354 Gen 3 moves + 18 Fairy moves);
- `data/moves_fairy.lua` — 18 Fairy moves;
- `data/learnsets_fairy.lua` — 43 Gen 3 species with CFRU's Gen 6 level-up
  Fairy moves: Disarming Voice, Draining Kiss, Play Rough, Fairy Wind,
  Moonblast, Baby-Doll Eyes. Charm / Moonlight / Sweet Kiss keep their native
  Gen 3 levels; `main.lua` merges this table into the ROM learnset.

Skipped because Gen 3 has no engine support: Misty Terrain, Fairy Lock,
Flower Shield, Aromatic Mist, Crafty Shield, Geomancy, Decorate, Tera Blast.
Draining Kiss uses the Gen 3 50% drain effect (not Gen 6's 75%).

On the fork, battle move menus tint the move name by matchup (green super
effective, yellow resisted, grey immune, default for 1x) and tint the word
`TYPE` by damage class (red physical, blue special, grey status). The summary
screen tints the move name itself instead; Emerald's palette has no red in the
move window's bank, so it borrows index 106 from the global 144-colour table.
Contest pages keep the native contest categories.

Mapped secondary effects: Play Rough 10% Atk -1, Moonblast 30% SpA -1,
Spirit Break 100% SpA -1, Strange Steam 20% confusion, Magical Torque 30%
confusion, Springtide Storm 30% Atk -1. Alluring Voice's conditional and
Sparkly Swirl's team-heal special cases are not modeled.

The move records carry a **string** effect id such as
`ATTACK_DOWN_SIDE_EFFECT`, not the numeric `battle_move_effects.h` value. The
engine's Gen 3 content writer (`UnifiedEffects.write`) owns that mapping; a
numeric value is rejected at load time. The mod also registers the FAIRY type
and its 324 matchups in the engine's `type_chart` registry before it registers
the moves, because the move writer validates every move type against that
registry. The runtime overlay is still what makes the `GEN 9` / `VANILLA`
switch instant.

`data.pokemon` is not rewritten; the runtime tables (`Pokemon._types`,
`Pokemon._learnsets`, `Moves._rom`, `Pokemon._battleMoves`) are the source of
truth while `GEN 9` is active.

## Generating data

The repository commits generated Lua so players do not need Node or Showdown.

The learnset table comes from CFRU's `src/Tables/level_up_learnsets.c`:

```sh
python3 tools/export_cfru_learnsets.py --cfru /path/to/Complete-Fire-Red-Upgrade
```

CFRU's Gen 3 species only list six of the 18 new Fairy moves at level-up.
Dazzling Gleam, Fleur Cannon, Light of Ruin, Floral Healing, Nature's
Madness, Sparkly Swirl, Spirit Break, Strange Steam, Misty Explosion,
Springtide Storm, Magical Torque and Alluring Voice have no level-up source
on Gen 3 species: they are TM/tutor moves, or belong to later generations.

```bash
python3 tools/export_showdown.py --showdown /path/to/pokemon-showdown
python3 tools/extract_fairy_icon.py --cfru /path/to/Complete-Fire-Red-Upgrade
```

`--showdown` and `--cfru` are explicit paths; the tools never embed a local
absolute path. `SHOWDOWN_DIR` and `CFRU_DIR` are accepted as fallbacks.

## Data sources

- Type chart, Pokédex types, move categories and learnsets:
  [Pokémon Showdown](https://github.com/smogon/pokemon-showdown) (MIT).
- Optional Fairy type icon: CFRU `graphics/Other/Type_Icons/Type_Icons.bmp`.
  The icon is not bundled in releases unless its redistribution is cleared;
  the text fallback works without it.

## Development

```bash
luajit tests/data_test.lua
luajit tests/main_smoke_test.lua
luajit tests/apply_test.lua
ENGINE_DIR=/path/to/gen1recomp luajit tests/engine_smoke_test.lua
ENGINE_DIR=/path/to/gen1recomp luajit tests/engine_effect_test.lua
```

### Live smoke test

`tests/live_smoke.lua` is an in-engine driver for a real ROM import. It is
not part of CI because it needs an imported cache:

```sh
POKEPORT_IDENTITY=<identity> POKEPORT_VERSION=firered \
  POKEPORT_DRIVER=tests/live_smoke.lua love .
```

Run it once per game (`firered`, `leafgreen`, `emerald`, `ruby`,
`sapphire`) from the engine checkout with this repository under `mods/`. It
covers the `BATTLE DATA` switch, the Gen 9 chart, the 18 Fairy species, the
18 Fairy moves, per-move physical/special, and the VANILLA restore.

### CI

`.github/workflows/ci.yml` validates the manifest and data tables, rejects
local absolute paths, runs `tests/data_test.lua`, and checks out the
`gen1recomp-ps-split` fork for an engine smoke test.

See `AGENTS.md` for the hard rules and the two-repository architecture.

## License

MIT for the code and the Lua data tables. Pokémon names, move names and
mechanics belong to their respective owners. This project ships no ROM and no
ROM-derived artwork.
