# Gen 9 Types & Battle Data for gen1recomp

A content mod for **gen1recomp** that brings a Gen 9 data layer to the Gen 3
games (FireRed, LeafGreen, Emerald) without replacing the engine.

## What it does

- Adds the **Fairy** type and the Gen 6+ 18-type chart.
- Reassigns the 18 Gen 3 species that gained Fairy in later generations.
- Changes four existing moves to their modern types:
  - Charm: Normal → Fairy
  - Moonlight: Normal → Fairy
  - Sweet Kiss: Normal → Fairy
  - Curse: ??? → Ghost
- Provides per-move physical/special categories when the engine supports them.
- Adds a small set of Gen 9 Fairy moves and level-up learnset patches.
- Optional enhancements implemented through public hooks:
  - EXP for catching
  - Party EXP Share
  - Trade evolution at level 40
  - HMs without knowing the move
  - Infinite TMs
  - IV/EV viewer (planned)

It does **not** add new abilities, Fairy TMs/HMs, visible wild Pokémon,
day/night, followers, or 3DS-specific features.

## Compatibility

| Engine | Gen 9 types/species/moves | Per-move physical/special | Battle menu category/effectiveness |
| --- | --- | --- | --- |
| Official gen1recomp | Yes | No (type-based fallback) | No |
| `gen1recomp-ps-split` | Yes | Yes | Yes |

The mod detects the engine capability at load time. On the official engine it
runs in **compat mode** and logs a warning: Play Rough is treated as a special
move because the engine has no per-move category yet.

## Install

1. Install a gen1recomp build.
2. Copy this folder into the game's `mods/` directory as
   `mods/types_mod_gen1recomp/`.
3. Enable **Gen 9 Types & Battle Data** in the mod manager.
4. Open **OPTIONS → ENHANCEMENTS**:
   - `BATTLE DATA`: `GEN 9` / `VANILLA`
   - individual enhancement toggles

The data mode can only be changed outside battle. In battle the option refuses
the change and keeps the current mode.

## Current scaffold state

The 18-type Gen 9 chart (`data/types.lua`), the 18 Fairy species
(`data/species_fairy.lua`) and the four existing move type changes
(`data/move_types_changed.lua`) are present. The chart was generated from
Showdown and contains all 324 matchups.

Still scaffolded and empty:

- `data/move_categories.lua` — per-move physical/special categories
- `data/moves_fairy.lua` — new Fairy moves
- `data/learnsets_fairy.lua` — Gen 9 level-up learnsets

Until those are generated, `BATTLE DATA → GEN 9` applies the type chart, the 18
species types and the four move type changes. It does not add Play Rough or
Moonblast yet.

## Generating data

The repository commits generated Lua so players do not need Node or Showdown.

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
ENGINE_DIR=/path/to/gen1recomp luajit tests/engine_smoke_test.lua
```

See `AGENTS.md` for the hard rules and the two-repository architecture.

## License

MIT for the code and the Lua data tables. Pokémon names, move names and
mechanics belong to their respective owners. This project ships no ROM and no
ROM-derived artwork.
