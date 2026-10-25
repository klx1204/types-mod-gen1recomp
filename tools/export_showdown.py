#!/usr/bin/env python3
"""Export Gen 9 tables from a Pokémon Showdown checkout.

Generates:
  data/types.lua           18-type chart (324 matchups)
  data/move_categories.lua Gen 3 move categories + new Fairy moves
  data/moves_fairy.lua     new Fairy moves with Gen 3-safe effects
  data/learnsets_fairy.lua Gen 9 level-up Fairy moves for Gen 3 species

Usage:
  python3 tools/export_showdown.py --showdown /path/to/pokemon-showdown
  SHOWDOWN_DIR=/path/to/pokemon-showdown python3 tools/export_showdown.py

No local absolute path is embedded in the generated files.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

TYPE_NAMES = [
    "NORMAL", "FIGHTING", "FLYING", "POISON", "GROUND", "ROCK", "BUG", "GHOST",
    "STEEL", "CURSE_TYPE", "FIRE", "WATER", "GRASS", "ELECTRIC", "PSYCHIC_TYPE",
    "ICE", "DRAGON", "DARK", "FAIRY",
]

SHOWDOWN_TO_INTERNAL = {
    "Normal": "NORMAL", "Fighting": "FIGHTING", "Flying": "FLYING",
    "Poison": "POISON", "Ground": "GROUND", "Rock": "ROCK", "Bug": "BUG",
    "Ghost": "GHOST", "Steel": "STEEL", "Fire": "FIRE", "Water": "WATER",
    "Grass": "GRASS", "Electric": "ELECTRIC", "Psychic": "PSYCHIC_TYPE",
    "Ice": "ICE", "Dragon": "DRAGON", "Dark": "DARK", "Fairy": "FAIRY",
}

MULTIPLIER = {0: 10, 1: 20, 2: 5, 3: 0}

# Gen 3-safe effects, from src/core/game3/battle/effect_ids.lua.
EFFECTS = {
    "DRAINING_KISS": (3, 0),      # ABSORB (50% in Gen 3; documented approximation)
    "DISARMING_VOICE": (17, 0),   # ALWAYS_HIT
    "BABY_DOLL_EYES": (18, 1),    # ATTACK_DOWN, priority +1
    "PLAY_NICE": (18, 0),         # ATTACK_DOWN
    "FLORAL_HEALING": (32, 0),    # RESTORE_HP
    "NATURES_MADNESS": (40, 0),   # SUPER_FANG
    "LIGHT_OF_RUIN": (48, 0),     # RECOIL
    "FLEUR_CANNON": (204, 0),     # OVERHEAT
    "MISTY_EXPLOSION": (7, 0),    # EXPLOSION
}

# Complex moves with no Gen 3 engine support; skip rather than ship a broken
# move. Documented in README.
SKIP_FAIRY = {
    "MISTY_TERRAIN", "FAIRY_LOCK", "FLOWER_SHIELD", "AROMATIC_MIST",
    "CRAFTY_SHIELD", "GEOMANCY", "DECORATE", "TERA_BLAST",
}

SPECIAL_SPECIES = {
    "Nidoran-F": "NIDORAN_F",
    "Nidoran-M": "NIDORAN_M",
    "Nidoran♀": "NIDORAN_F",
    "Nidoran♂": "NIDORAN_M",
    "Farfetch'd": "FARFETCHD",
    "Mr. Mime": "MR_MIME",
    "Ho-Oh": "HO_OH",
    "Porygon2": "PORYGON2",
    "Deoxys": "DEOXYS",
}


def fail(message: str) -> "None":
    print(f"export_showdown: {message}", file=sys.stderr)
    raise SystemExit(2)


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except OSError as exc:
        fail(f"cannot read {path}: {exc}")


def species_macro(name: str) -> str:
    if name in SPECIAL_SPECIES:
        return SPECIAL_SPECIES[name]
    value = name.upper().replace("♀", "_F").replace("♂", "_M")
    value = re.sub(r"[^A-Z0-9]+", "_", value).strip("_")
    return value


def move_macro(name: str) -> str:
    value = name.upper().replace("'", "").replace(".", "")
    value = re.sub(r"[^A-Z0-9]+", "_", value).strip("_")
    return value


def iter_entries(source: str):
    """Yield (key, block) for one-tab object entries in Showdown data files."""
    pattern = re.compile(r"^\t([a-z0-9-]+): \{", re.M)
    for match in pattern.finditer(source):
        brace = source.find("{", match.start())
        if brace == -1:
            continue
        depth = 0
        end = brace
        for i in range(brace, len(source)):
            if source[i] == "{":
                depth += 1
            elif source[i] == "}":
                depth -= 1
                if depth == 0:
                    end = i
                    break
        yield match.group(1), source[match.start():end + 1]


def field_string(block: str, name: str) -> str | None:
    match = re.search(r'^\s*' + re.escape(name) + r':\s*"([^"]*)"', block, re.M)
    return match.group(1) if match else None


def field_number(block: str, name: str) -> int | None:
    match = re.search(r"^\s*" + re.escape(name) + r":\s*(-?\d+)", block, re.M)
    return int(match.group(1)) if match else None


def field_types(block: str) -> list[str]:
    match = re.search(r"^\s*types:\s*\[(.*?)\]", block, re.M)
    if not match:
        return []
    return re.findall(r'"([^"]+)"', match.group(1))


def has_field(block: str, name: str) -> bool:
    return re.search(r"^\s*" + re.escape(name) + r":", block, re.M) is not None


def parse_damage_taken(source: str) -> dict[str, dict[str, int]]:
    result: dict[str, dict[str, int]] = {}
    type_re = re.compile(r"^\t([a-z]+):\s*\{", re.M)
    for match in type_re.finditer(source):
        name = match.group(1)
        start = source.find("damageTaken:", match.start())
        if start == -1:
            continue
        brace = source.find("{", start)
        if brace == -1:
            continue
        depth = 0
        end = brace
        for i in range(brace, len(source)):
            if source[i] == "{":
                depth += 1
            elif source[i] == "}":
                depth -= 1
                if depth == 0:
                    end = i
                    break
        block = source[brace + 1:end]
        values: dict[str, int] = {}
        for key, value in re.findall(r"([A-Za-z]+):\s*(\d+)", block):
            if key == "prankster":
                continue
            values[key] = int(value)
        if values:
            result[name] = values
    return result


def build_matchups(damage_taken: dict[str, dict[str, int]]) -> list[tuple[str, str, int]]:
    rows: list[tuple[str, str, int]] = []
    for defender, attackers in sorted(damage_taken.items()):
        defender_internal = SHOWDOWN_TO_INTERNAL.get(defender.capitalize())
        if not defender_internal:
            continue
        for attacker, value in sorted(attackers.items()):
            attacker_internal = SHOWDOWN_TO_INTERNAL.get(attacker)
            if not attacker_internal or value not in MULTIPLIER:
                continue
            rows.append((attacker_internal, defender_internal, MULTIPLIER[value]))
    return rows


def parse_pokedex(source: str) -> dict[str, dict]:
    out = {}
    for key, block in iter_entries(source):
        num = field_number(block, "num")
        name = field_string(block, "name")
        if num is None or not name:
            continue
        out[key] = {
            "num": num,
            "name": name,
            "types": field_types(block),
            "form": has_field(block, "baseSpecies"),
        }
    return out


def parse_moves(source: str) -> dict[str, dict]:
    out = {}
    for key, block in iter_entries(source):
        name = field_string(block, "name")
        move_type = field_string(block, "type")
        if not name or not move_type:
            continue
        out[key] = {
            "key": key,
            "num": field_number(block, "num") or 0,
            "name": name,
            "type": move_type,
            "category": field_string(block, "category") or "Status",
            "basePower": field_number(block, "basePower") or 0,
            "accuracy": 100 if re.search(r"^\s*accuracy:\s*true", block, re.M)
                else (field_number(block, "accuracy") or 100),
            "pp": field_number(block, "pp") or 5,
            "priority": field_number(block, "priority") or 0,
            "isZ": has_field(block, "isZ"),
            "isMax": has_field(block, "isMax"),
        }
    return out


def parse_learnsets(source: str) -> dict[str, dict[str, int]]:
    out = {}
    for key, block in iter_entries(source):
        match = re.search(r"^\t\tlearnset:\s*\{", block, re.M)
        if not match:
            continue
        brace = block.find("{", match.start())
        depth = 0
        end = brace
        for i in range(brace, len(block)):
            if block[i] == "{":
                depth += 1
            elif block[i] == "}":
                depth -= 1
                if depth == 0:
                    end = i
                    break
        learn = block[brace + 1:end]
        moves: dict[str, int] = {}
        for move_key, tags in re.findall(r"^\s*([a-z0-9]+):\s*\[([^\]]*)\]", learn, re.M):
            level = re.search(r'"9L(\d+)"', tags)
            if level:
                moves[move_key] = int(level.group(1))
        if moves:
            out[key] = moves
    return out


def emit_types(rows: list[tuple[str, str, int]], out: Path) -> None:
    index_lines = "\n".join(f"    {name} = {i}," for i, name in enumerate(TYPE_NAMES))
    name_lines = "\n".join(f'    [{i}] = "{name}",' for i, name in enumerate(TYPE_NAMES))
    physical = ", ".join(f"[{i}] = true" for i in range(9))
    matchup_lines = "\n".join(
        f'    {{ attacker = "{a}", defender = "{d}", multiplier = {m} }},'
        for a, d, m in rows
    )
    out.write_text(f"""-- Generated by tools/export_showdown.py from Pokémon Showdown.
-- Do not edit by hand. `complete = true` means the full chart is present.
return {{
  complete = true,
  fairyIndex = 18,
  index = {{
{index_lines}
  }},
  names = {{
{name_lines}
  }},
  physical = {{ {physical}, [18] = false }},
  matchups = {{
{matchup_lines}
  }},
}}
""", encoding="utf-8")


def build_fairy_moves(moves: dict[str, dict]) -> list[dict]:
    selected = []
    for move in moves.values():
        if move["type"] != "Fairy" or move["isZ"] or move["isMax"]:
            continue
        # Charm / Moonlight / Sweet Kiss already exist in Gen 3 and are handled
        # by data/move_types_changed.lua, not by this new-move table.
        if move["num"] <= 354:
            continue
        macro = move_macro(move["name"])
        if macro in SKIP_FAIRY:
            continue
        selected.append((move, macro))
    selected.sort(key=lambda item: (item[0]["num"], item[1]))
    out = []
    for offset, (move, macro) in enumerate(selected):
        effect, priority = EFFECTS.get(macro, (0, move["priority"]))
        power = move["basePower"]
        # SUPER_FANG-style effects need a non-zero power to enter the damage path.
        if effect == 40 and power == 0:
            power = 1
        out.append({
            "id": macro,
            "name": move["name"],
            "index": 355 + offset,
            "power": power,
            "accuracy": move["accuracy"],
            "pp": move["pp"],
            "priority": priority,
            "effect": effect,
        })
    return out


def emit_fairy_moves(moves: list[dict], out: Path) -> None:
    lines = []
    for move in moves:
        lines.append(
            '  %s = { name = %r, index = %d, type = "FAIRY", power = %d, '
            "accuracy = %d, pp = %d, priority = %d, effect = %d },"
            % (move["id"], move["name"], move["index"], move["power"],
               move["accuracy"], move["pp"], move["priority"], move["effect"])
        )
    out.write_text(
        "-- Generated by tools/export_showdown.py from Pokémon Showdown.\n"
        "-- Category is intentionally absent: it lives in move_categories.lua.\n"
        "return {\n" + "\n".join(lines) + "\n}\n",
        encoding="utf-8",
    )


def build_categories(moves: dict[str, dict], fairy: list[dict]) -> dict[str, str]:
    out = {}
    for move in moves.values():
        if 1 <= move["num"] <= 354:
            # Hidden Power's 17 type forms reuse num 237; keep the base move only.
            if move["name"].startswith("Hidden Power "):
                continue
            out[move_macro(move["name"])] = move["category"].lower()
    for move in fairy:
        source = next((m for m in moves.values() if move_macro(m["name"]) == move["id"]), None)
        if source:
            out[move["id"]] = source["category"].lower()
    return out


def emit_categories(categories: dict[str, str], out: Path) -> None:
    lines = [f'  {key} = "{value}",' for key, value in sorted(categories.items())]
    out.write_text(
        "-- Generated by tools/export_showdown.py from Pokémon Showdown.\n"
        "-- Gen 3 moves plus the new Fairy moves.\n"
        "return {\n" + "\n".join(lines) + "\n}\n",
        encoding="utf-8",
    )


def build_learnsets(pokedex: dict[str, dict], learnsets: dict[str, dict[str, int]],
                    fairy: list[dict]) -> dict[str, list[dict]]:
    available = {move["id"] for move in fairy}
    available |= {"CHARM", "MOONLIGHT", "SWEET_KISS"}
    out: dict[str, list[dict]] = {}
    for key, species in pokedex.items():
        if species["num"] < 1 or species["num"] > 386 or species["form"]:
            continue
        moves = learnsets.get(key) or {}
        rows = []
        for move_key, level in moves.items():
            macro = move_macro(move_key.replace("-", " "))
            if macro in available:
                rows.append({"level": level, "move": macro})
        if rows:
            rows.sort(key=lambda row: (row["level"], row["move"]))
            out[species_macro(species["name"])] = rows
    return out


def emit_learnsets(learnsets: dict[str, list[dict]], out: Path) -> None:
    lines = []
    for species in sorted(learnsets):
        rows = learnsets[species]
        body = ", ".join('{ level = %d, move = "%s" }' % (r["level"], r["move"]) for r in rows)
        lines.append(f"  {species} = {{ {body} }},")
    out.write_text(
        "-- Generated by tools/export_showdown.py from Pokémon Showdown.\n"
        "-- Gen 9 level-up Fairy moves for Gen 3 species. Names are resolved\n"
        "-- to numeric ids by main.lua after the new moves are registered.\n"
        "return {\n" + "\n".join(lines) + "\n}\n",
        encoding="utf-8",
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--showdown", default=os.environ.get("SHOWDOWN_DIR"),
                        help="path to a pokemon-showdown checkout")
    parser.add_argument("--types-out", default="data/types.lua")
    parser.add_argument("--moves-out", default="data/moves_fairy.lua")
    parser.add_argument("--categories-out", default="data/move_categories.lua")
    parser.add_argument("--learnsets-out", default="data/learnsets_fairy.lua")
    args = parser.parse_args()

    if not args.showdown:
        fail("pass --showdown <path> or set SHOWDOWN_DIR")
    root = Path(args.showdown).expanduser().resolve()
    typechart = root / "data" / "typechart.ts"
    pokedex_path = root / "data" / "pokedex.ts"
    moves_path = root / "data" / "moves.ts"
    learnsets_path = root / "data" / "learnsets.ts"
    for path in (typechart, pokedex_path, moves_path, learnsets_path):
        if not path.is_file():
            fail(f"missing {path}")

    damage_taken = parse_damage_taken(read_text(typechart))
    if "fairy" not in damage_taken:
        fail("typechart.ts did not contain a Fairy entry")
    matchups = build_matchups(damage_taken)
    if len(matchups) < 300:
        fail(f"only {len(matchups)} matchups parsed; refusing a partial chart")

    pokedex = parse_pokedex(read_text(pokedex_path))
    moves = parse_moves(read_text(moves_path))
    learnsets = parse_learnsets(read_text(learnsets_path))
    fairy = build_fairy_moves(moves)
    if len(fairy) < 15:
        fail(f"only {len(fairy)} Fairy moves found; refusing a partial table")
    categories = build_categories(moves, fairy)
    gen3_learnsets = build_learnsets(pokedex, learnsets, fairy)
    if len(gen3_learnsets) < 10:
        fail(f"only {len(gen3_learnsets)} species learnsets found; refusing a partial table")

    emit_types(matchups, Path(args.types_out))
    emit_fairy_moves(fairy, Path(args.moves_out))
    emit_categories(categories, Path(args.categories_out))
    emit_learnsets(gen3_learnsets, Path(args.learnsets_out))

    print(f"wrote {args.types_out} ({len(matchups)} matchups)")
    print(f"wrote {args.moves_out} ({len(fairy)} Fairy moves)")
    print(f"wrote {args.categories_out} ({len(categories)} categories)")
    print(f"wrote {args.learnsets_out} ({len(gen3_learnsets)} species)")


if __name__ == "__main__":
    main()
