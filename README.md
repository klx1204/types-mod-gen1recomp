# Gen 9 Types & Battle Data for gen1recomp

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
| `gen1recomp-ps-split` | Yes | Yes (after the fork call sites are wired) | Yes (same condition) |

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

## Current data state

Generated from Showdown and committed:

- `data/types.lua` — 18-type chart, 324 matchups;
- `data/species_fairy.lua` — the 18 Gen 3 species that gained Fairy; every
  other Gen 3 species keeps its Gen 3 types, which are identical to Gen 9;
- `data/move_types_changed.lua` — Charm, Moonlight, Sweet Kiss, Curse;
- `data/move_categories.lua` — 372 categories (354 Gen 3 moves + 18 Fairy moves);
- `data/moves_fairy.lua` — 18 Fairy moves;
- `data/learnsets_fairy.lua` — 40 Gen 3 species with Gen 9 level-up Fairy moves.

Skipped because Gen 3 has no engine support: Misty Terrain, Fairy Lock,
Flower Shield, Aromatic Mist, Crafty Shield, Geomancy, Decorate, Tera Blast.
Draining Kiss uses the Gen 3 50% drain effect (not Gen 6's 75%).

Mapped secondary effects: Play Rough 10% Atk -1, Moonblast 30% SpA -1,
Spirit Break 100% SpA -1, Strange Steam 20% confusion, Magical Torque 30%
confusion, Springtide Storm 30% Atk -1. Alluring Voice's conditional and
Sparkly Swirl's team-heal special cases are not modeled.

`data.pokemon` is not rewritten; the runtime tables (`Pokemon._types`,
`Pokemon._learnsets`, `Moves._rom`, `Pokemon._battleMoves`) are the source of
truth while `GEN 9` is active.

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
luajit tests/main_smoke_test.lua
luajit tests/apply_test.lua
ENGINE_DIR=/path/to/gen1recomp luajit tests/engine_smoke_test.lua
```

### CI

`.github/workflows/ci.yml` validates the manifest and data tables, rejects
local absolute paths, runs `tests/data_test.lua`, and checks out the
`gen1recomp-ps-split` fork for an engine smoke test.

See `AGENTS.md` for the hard rules and the two-repository architecture.

## License

MIT for the code and the Lua data tables. Pokémon names, move names and
mechanics belong to their respective owners. This project ships no ROM and no
ROM-derived artwork.
