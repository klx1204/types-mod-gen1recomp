#!/usr/bin/env python3
"""Export Gen 3 level-up Fairy moves from CFRU's Gen 6 learnsets.

CFRU ships a Gen 6-shaped level-up table in
`src/Tables/level_up_learnsets.c`.  It covers every Gen 3 species and already
places Disarming Voice, Play Rough, Moonblast and friends at official levels,
which is what the mod needs for its 18 new moves.

Only the 18 new Fairy moves are written.  Charm / Moonlight / Sweet Kiss are
native Gen 3 moves whose Gen 3 levels the mod keeps: `main.lua` merges this
table into the ROM learnset, so leaving them out preserves the original
levels.

Usage:
    python3 tools/export_cfru_learnsets.py --cfru /path/to/CFRU
    CFRU_DIR=/path/to/CFRU python3 tools/export_cfru_learnsets.py

No local absolute path is embedded in the generated file.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

# CFRU's species ids are FireRed's internal order, not the national dex:
# SPECIES_RALTS is 392 there.  Match Gen 3 by name instead.
GEN3_SPECIES = {
    "ABRA": "ABRA",
    "ABSOL": "ABSOL",
    "AERODACTYL": "AERODACTYL",
    "AGGRON": "AGGRON",
    "AIPOM": "AIPOM",
    "ALAKAZAM": "ALAKAZAM",
    "ALTARIA": "ALTARIA",
    "AMPHAROS": "AMPHAROS",
    "ANORITH": "ANORITH",
    "ARBOK": "ARBOK",
    "ARCANINE": "ARCANINE",
    "ARIADOS": "ARIADOS",
    "ARMALDO": "ARMALDO",
    "ARON": "ARON",
    "ARTICUNO": "ARTICUNO",
    "AZUMARILL": "AZUMARILL",
    "AZURILL": "AZURILL",
    "BAGON": "BAGON",
    "BALTOY": "BALTOY",
    "BANETTE": "BANETTE",
    "BARBOACH": "BARBOACH",
    "BAYLEEF": "BAYLEEF",
    "BEAUTIFLY": "BEAUTIFLY",
    "BEEDRILL": "BEEDRILL",
    "BELDUM": "BELDUM",
    "BELLOSSOM": "BELLOSSOM",
    "BELLSPROUT": "BELLSPROUT",
    "BLASTOISE": "BLASTOISE",
    "BLAZIKEN": "BLAZIKEN",
    "BLISSEY": "BLISSEY",
    "BRELOOM": "BRELOOM",
    "BULBASAUR": "BULBASAUR",
    "BUTTERFREE": "BUTTERFREE",
    "CACNEA": "CACNEA",
    "CACTURNE": "CACTURNE",
    "CAMERUPT": "CAMERUPT",
    "CARVANHA": "CARVANHA",
    "CASCOON": "CASCOON",
    "CASTFORM": "CASTFORM",
    "CATERPIE": "CATERPIE",
    "CELEBI": "CELEBI",
    "CHANSEY": "CHANSEY",
    "CHARIZARD": "CHARIZARD",
    "CHARMANDER": "CHARMANDER",
    "CHARMELEON": "CHARMELEON",
    "CHIKORITA": "CHIKORITA",
    "CHIMECHO": "CHIMECHO",
    "CHINCHOU": "CHINCHOU",
    "CLAMPERL": "CLAMPERL",
    "CLAYDOL": "CLAYDOL",
    "CLEFABLE": "CLEFABLE",
    "CLEFAIRY": "CLEFAIRY",
    "CLEFFA": "CLEFFA",
    "CLOYSTER": "CLOYSTER",
    "COMBUSKEN": "COMBUSKEN",
    "CORPHISH": "CORPHISH",
    "CORSOLA": "CORSOLA",
    "CRADILY": "CRADILY",
    "CRAWDAUNT": "CRAWDAUNT",
    "CROBAT": "CROBAT",
    "CROCONAW": "CROCONAW",
    "CUBONE": "CUBONE",
    "CYNDAQUIL": "CYNDAQUIL",
    "DELCATTY": "DELCATTY",
    "DELIBIRD": "DELIBIRD",
    "DEOXYS": "DEOXYS",
    "DEWGONG": "DEWGONG",
    "DIGLETT": "DIGLETT",
    "DITTO": "DITTO",
    "DODRIO": "DODRIO",
    "DODUO": "DODUO",
    "DONPHAN": "DONPHAN",
    "DRAGONAIR": "DRAGONAIR",
    "DRAGONITE": "DRAGONITE",
    "DRATINI": "DRATINI",
    "DROWZEE": "DROWZEE",
    "DUGTRIO": "DUGTRIO",
    "DUNSPARCE": "DUNSPARCE",
    "DUSCLOPS": "DUSCLOPS",
    "DUSKULL": "DUSKULL",
    "DUSTOX": "DUSTOX",
    "EEVEE": "EEVEE",
    "EKANS": "EKANS",
    "ELECTABUZZ": "ELECTABUZZ",
    "ELECTRIKE": "ELECTRIKE",
    "ELECTRODE": "ELECTRODE",
    "ELEKID": "ELEKID",
    "ENTEI": "ENTEI",
    "ESPEON": "ESPEON",
    "EXEGGCUTE": "EXEGGCUTE",
    "EXEGGUTOR": "EXEGGUTOR",
    "EXPLOUD": "EXPLOUD",
    "FARFETCHU2019D": "FARFETCH_U2019D",
    "FEAROW": "FEAROW",
    "FEEBAS": "FEEBAS",
    "FERALIGATR": "FERALIGATR",
    "FLAAFFY": "FLAAFFY",
    "FLAREON": "FLAREON",
    "FLYGON": "FLYGON",
    "FORRETRESS": "FORRETRESS",
    "FURRET": "FURRET",
    "GARDEVOIR": "GARDEVOIR",
    "GASTLY": "GASTLY",
    "GENGAR": "GENGAR",
    "GEODUDE": "GEODUDE",
    "GIRAFARIG": "GIRAFARIG",
    "GLALIE": "GLALIE",
    "GLIGAR": "GLIGAR",
    "GLOOM": "GLOOM",
    "GOLBAT": "GOLBAT",
    "GOLDEEN": "GOLDEEN",
    "GOLDUCK": "GOLDUCK",
    "GOLEM": "GOLEM",
    "GOREBYSS": "GOREBYSS",
    "GRANBULL": "GRANBULL",
    "GRAVELER": "GRAVELER",
    "GRIMER": "GRIMER",
    "GROUDON": "GROUDON",
    "GROVYLE": "GROVYLE",
    "GROWLITHE": "GROWLITHE",
    "GRUMPIG": "GRUMPIG",
    "GULPIN": "GULPIN",
    "GYARADOS": "GYARADOS",
    "HARIYAMA": "HARIYAMA",
    "HAUNTER": "HAUNTER",
    "HERACROSS": "HERACROSS",
    "HITMONCHAN": "HITMONCHAN",
    "HITMONLEE": "HITMONLEE",
    "HITMONTOP": "HITMONTOP",
    "HOOH": "HO_OH",
    "HOOTHOOT": "HOOTHOOT",
    "HOPPIP": "HOPPIP",
    "HORSEA": "HORSEA",
    "HOUNDOOM": "HOUNDOOM",
    "HOUNDOUR": "HOUNDOUR",
    "HUNTAIL": "HUNTAIL",
    "HYPNO": "HYPNO",
    "IGGLYBUFF": "IGGLYBUFF",
    "ILLUMISE": "ILLUMISE",
    "IVYSAUR": "IVYSAUR",
    "JIGGLYPUFF": "JIGGLYPUFF",
    "JIRACHI": "JIRACHI",
    "JOLTEON": "JOLTEON",
    "JUMPLUFF": "JUMPLUFF",
    "JYNX": "JYNX",
    "KABUTO": "KABUTO",
    "KABUTOPS": "KABUTOPS",
    "KADABRA": "KADABRA",
    "KAKUNA": "KAKUNA",
    "KANGASKHAN": "KANGASKHAN",
    "KECLEON": "KECLEON",
    "KINGDRA": "KINGDRA",
    "KINGLER": "KINGLER",
    "KIRLIA": "KIRLIA",
    "KOFFING": "KOFFING",
    "KRABBY": "KRABBY",
    "KYOGRE": "KYOGRE",
    "LAIRON": "LAIRON",
    "LANTURN": "LANTURN",
    "LAPRAS": "LAPRAS",
    "LARVITAR": "LARVITAR",
    "LATIAS": "LATIAS",
    "LATIOS": "LATIOS",
    "LEDIAN": "LEDIAN",
    "LEDYBA": "LEDYBA",
    "LICKITUNG": "LICKITUNG",
    "LILEEP": "LILEEP",
    "LINOONE": "LINOONE",
    "LOMBRE": "LOMBRE",
    "LOTAD": "LOTAD",
    "LOUDRED": "LOUDRED",
    "LUDICOLO": "LUDICOLO",
    "LUGIA": "LUGIA",
    "LUNATONE": "LUNATONE",
    "LUVDISC": "LUVDISC",
    "MACHAMP": "MACHAMP",
    "MACHOKE": "MACHOKE",
    "MACHOP": "MACHOP",
    "MAGBY": "MAGBY",
    "MAGCARGO": "MAGCARGO",
    "MAGIKARP": "MAGIKARP",
    "MAGMAR": "MAGMAR",
    "MAGNEMITE": "MAGNEMITE",
    "MAGNETON": "MAGNETON",
    "MAKUHITA": "MAKUHITA",
    "MANECTRIC": "MANECTRIC",
    "MANKEY": "MANKEY",
    "MANTINE": "MANTINE",
    "MAREEP": "MAREEP",
    "MARILL": "MARILL",
    "MAROWAK": "MAROWAK",
    "MARSHTOMP": "MARSHTOMP",
    "MASQUERAIN": "MASQUERAIN",
    "MAWILE": "MAWILE",
    "MEDICHAM": "MEDICHAM",
    "MEDITITE": "MEDITITE",
    "MEGANIUM": "MEGANIUM",
    "MEOWTH": "MEOWTH",
    "METAGROSS": "METAGROSS",
    "METANG": "METANG",
    "METAPOD": "METAPOD",
    "MEW": "MEW",
    "MEWTWO": "MEWTWO",
    "MIGHTYENA": "MIGHTYENA",
    "MILOTIC": "MILOTIC",
    "MILTANK": "MILTANK",
    "MINUN": "MINUN",
    "MISDREAVUS": "MISDREAVUS",
    "MOLTRES": "MOLTRES",
    "MRMIME": "MR_MIME",
    "MUDKIP": "MUDKIP",
    "MUK": "MUK",
    "MURKROW": "MURKROW",
    "NATU": "NATU",
    "NIDOKING": "NIDOKING",
    "NIDOQUEEN": "NIDOQUEEN",
    "NIDORANF": "NIDORAN_F",
    "NIDORANM": "NIDORAN_M",
    "NIDORINA": "NIDORINA",
    "NIDORINO": "NIDORINO",
    "NINCADA": "NINCADA",
    "NINETALES": "NINETALES",
    "NINJASK": "NINJASK",
    "NOCTOWL": "NOCTOWL",
    "NOSEPASS": "NOSEPASS",
    "NUMEL": "NUMEL",
    "NUZLEAF": "NUZLEAF",
    "OCTILLERY": "OCTILLERY",
    "ODDISH": "ODDISH",
    "OMANYTE": "OMANYTE",
    "OMASTAR": "OMASTAR",
    "ONIX": "ONIX",
    "PARAS": "PARAS",
    "PARASECT": "PARASECT",
    "PELIPPER": "PELIPPER",
    "PERSIAN": "PERSIAN",
    "PHANPY": "PHANPY",
    "PICHU": "PICHU",
    "PIDGEOT": "PIDGEOT",
    "PIDGEOTTO": "PIDGEOTTO",
    "PIDGEY": "PIDGEY",
    "PIKACHU": "PIKACHU",
    "PILOSWINE": "PILOSWINE",
    "PINECO": "PINECO",
    "PINSIR": "PINSIR",
    "PLUSLE": "PLUSLE",
    "POLITOED": "POLITOED",
    "POLIWAG": "POLIWAG",
    "POLIWHIRL": "POLIWHIRL",
    "POLIWRATH": "POLIWRATH",
    "PONYTA": "PONYTA",
    "POOCHYENA": "POOCHYENA",
    "PORYGON": "PORYGON",
    "PORYGON2": "PORYGON2",
    "PRIMEAPE": "PRIMEAPE",
    "PSYDUCK": "PSYDUCK",
    "PUPITAR": "PUPITAR",
    "QUAGSIRE": "QUAGSIRE",
    "QUILAVA": "QUILAVA",
    "QWILFISH": "QWILFISH",
    "RAICHU": "RAICHU",
    "RAIKOU": "RAIKOU",
    "RALTS": "RALTS",
    "RAPIDASH": "RAPIDASH",
    "RATICATE": "RATICATE",
    "RATTATA": "RATTATA",
    "RAYQUAZA": "RAYQUAZA",
    "REGICE": "REGICE",
    "REGIROCK": "REGIROCK",
    "REGISTEEL": "REGISTEEL",
    "RELICANTH": "RELICANTH",
    "REMORAID": "REMORAID",
    "RHYDON": "RHYDON",
    "RHYHORN": "RHYHORN",
    "ROSELIA": "ROSELIA",
    "SABLEYE": "SABLEYE",
    "SALAMENCE": "SALAMENCE",
    "SANDSHREW": "SANDSHREW",
    "SANDSLASH": "SANDSLASH",
    "SCEPTILE": "SCEPTILE",
    "SCIZOR": "SCIZOR",
    "SCYTHER": "SCYTHER",
    "SEADRA": "SEADRA",
    "SEAKING": "SEAKING",
    "SEALEO": "SEALEO",
    "SEEDOT": "SEEDOT",
    "SEEL": "SEEL",
    "SENTRET": "SENTRET",
    "SEVIPER": "SEVIPER",
    "SHARPEDO": "SHARPEDO",
    "SHEDINJA": "SHEDINJA",
    "SHELGON": "SHELGON",
    "SHELLDER": "SHELLDER",
    "SHIFTRY": "SHIFTRY",
    "SHROOMISH": "SHROOMISH",
    "SHUCKLE": "SHUCKLE",
    "SHUPPET": "SHUPPET",
    "SILCOON": "SILCOON",
    "SKARMORY": "SKARMORY",
    "SKIPLOOM": "SKIPLOOM",
    "SKITTY": "SKITTY",
    "SLAKING": "SLAKING",
    "SLAKOTH": "SLAKOTH",
    "SLOWBRO": "SLOWBRO",
    "SLOWKING": "SLOWKING",
    "SLOWPOKE": "SLOWPOKE",
    "SLUGMA": "SLUGMA",
    "SMEARGLE": "SMEARGLE",
    "SMOOCHUM": "SMOOCHUM",
    "SNEASEL": "SNEASEL",
    "SNORLAX": "SNORLAX",
    "SNORUNT": "SNORUNT",
    "SNUBBULL": "SNUBBULL",
    "SOLROCK": "SOLROCK",
    "SPEAROW": "SPEAROW",
    "SPHEAL": "SPHEAL",
    "SPINARAK": "SPINARAK",
    "SPINDA": "SPINDA",
    "SPOINK": "SPOINK",
    "SQUIRTLE": "SQUIRTLE",
    "STANTLER": "STANTLER",
    "STARMIE": "STARMIE",
    "STARYU": "STARYU",
    "STEELIX": "STEELIX",
    "SUDOWOODO": "SUDOWOODO",
    "SUICUNE": "SUICUNE",
    "SUNFLORA": "SUNFLORA",
    "SUNKERN": "SUNKERN",
    "SURSKIT": "SURSKIT",
    "SWABLU": "SWABLU",
    "SWALOT": "SWALOT",
    "SWAMPERT": "SWAMPERT",
    "SWELLOW": "SWELLOW",
    "SWINUB": "SWINUB",
    "TAILLOW": "TAILLOW",
    "TANGELA": "TANGELA",
    "TAUROS": "TAUROS",
    "TEDDIURSA": "TEDDIURSA",
    "TENTACOOL": "TENTACOOL",
    "TENTACRUEL": "TENTACRUEL",
    "TOGEPI": "TOGEPI",
    "TOGETIC": "TOGETIC",
    "TORCHIC": "TORCHIC",
    "TORKOAL": "TORKOAL",
    "TOTODILE": "TOTODILE",
    "TRAPINCH": "TRAPINCH",
    "TREECKO": "TREECKO",
    "TROPIUS": "TROPIUS",
    "TYPHLOSION": "TYPHLOSION",
    "TYRANITAR": "TYRANITAR",
    "TYROGUE": "TYROGUE",
    "UMBREON": "UMBREON",
    "UNOWN": "UNOWN",
    "URSARING": "URSARING",
    "VAPOREON": "VAPOREON",
    "VENOMOTH": "VENOMOTH",
    "VENONAT": "VENONAT",
    "VENUSAUR": "VENUSAUR",
    "VIBRAVA": "VIBRAVA",
    "VICTREEBEL": "VICTREEBEL",
    "VIGOROTH": "VIGOROTH",
    "VILEPLUME": "VILEPLUME",
    "VOLBEAT": "VOLBEAT",
    "VOLTORB": "VOLTORB",
    "VULPIX": "VULPIX",
    "WAILMER": "WAILMER",
    "WAILORD": "WAILORD",
    "WALREIN": "WALREIN",
    "WARTORTLE": "WARTORTLE",
    "WEEDLE": "WEEDLE",
    "WEEPINBELL": "WEEPINBELL",
    "WEEZING": "WEEZING",
    "WHISCASH": "WHISCASH",
    "WHISMUR": "WHISMUR",
    "WIGGLYTUFF": "WIGGLYTUFF",
    "WINGULL": "WINGULL",
    "WOBBUFFET": "WOBBUFFET",
    "WOOPER": "WOOPER",
    "WURMPLE": "WURMPLE",
    "WYNAUT": "WYNAUT",
    "XATU": "XATU",
    "YANMA": "YANMA",
    "ZANGOOSE": "ZANGOOSE",
    "ZAPDOS": "ZAPDOS",
    "ZIGZAGOON": "ZIGZAGOON",
    "ZUBAT": "ZUBAT",
}

# CFRU constant suffix -> mod move id.
FAIRY_MOVES = {
    "DISARMINGVOICE": "DISARMING_VOICE",
    "DRAININGKISS": "DRAINING_KISS",
    "PLAYROUGH": "PLAY_ROUGH",
    "FAIRYWIND": "FAIRY_WIND",
    "MOONBLAST": "MOONBLAST",
    "DAZZLINGGLEAM": "DAZZLING_GLEAM",
    "BABYDOLLEYES": "BABY_DOLL_EYES",
    "LIGHTOFRUIN": "LIGHT_OF_RUIN",
    "FLORALHEALING": "FLORAL_HEALING",
    "FLEURCANNON": "FLEUR_CANNON",
    "NATURESMADNESS": "NATURES_MADNESS",
    "SPARKLYSWIRL": "SPARKLY_SWIRL",
    "SPIRITBREAK": "SPIRIT_BREAK",
    "STRANGESTEAM": "STRANGE_STEAM",
    "MISTYEXPLOSION": "MISTY_EXPLOSION",
    "SPRINGTIDESTORM": "SPRINGTIDE_STORM",
    "MAGICALTORQUE": "MAGICAL_TORQUE",
    "ALLURINGVOICE": "ALLURING_VOICE",
}


def fail(message: str) -> "None":
    print(f"export_cfru_learnsets: {message}", file=sys.stderr)
    raise SystemExit(1)


def norm(value: str) -> str:
    return re.sub(r"[^A-Z0-9]", "", value.upper())


def parse_species(root: Path) -> dict[str, str]:
    header = root / "include" / "constants" / "species.h"
    if not header.is_file():
        fail(f"missing {header}")
    text = header.read_text(encoding="utf-8", errors="replace")
    out = {}
    for name in re.findall(r"#define\s+SPECIES_(\w+)\s+(?:0x[0-9A-Fa-f]+|\d+)", text):
        key = norm(name)
        if key in GEN3_SPECIES:
            out[key] = GEN3_SPECIES[key]
    return out


def parse_learnsets(root: Path) -> dict[str, list[dict]]:
    table = root / "src" / "Tables" / "level_up_learnsets.c"
    if not table.is_file():
        fail(f"missing {table}")
    text = table.read_text(encoding="utf-8", errors="replace")
    out = {}
    blocks = re.findall(
        r"static\s+const\s+struct\s+LevelUpMove\s+s(\w+)LevelUpLearnset\[\]\s*=\s*\{(.*?)LEVEL_UP_END",
        text,
        re.S,
    )
    if not blocks:
        fail("no LevelUpLearnset tables found")
    for species, body in blocks:
        # CFRU lists some moves twice (initial + relearn, e.g. Gardevoir
        # Moonblast at 1 and 62).  Keep the earliest level.
        earliest = {}
        for level, move in re.findall(r"LEVEL_UP_MOVE\(\s*(\d+)\s*,\s*MOVE_(\w+)\s*\)", body):
            mod_name = FAIRY_MOVES.get(move)
            if mod_name:
                earliest[mod_name] = min(earliest.get(mod_name, 999), int(level))
        if earliest:
            out[species.upper()] = [
                {"level": level, "move": move} for move, level in earliest.items()
            ]
    return out


def emit(learnsets: dict[str, list[dict]], out: Path) -> None:
    lines = []
    for species in sorted(learnsets):
        rows = sorted(learnsets[species], key=lambda row: (row["level"], row["move"]))
        body = ", ".join(
            '{ level = %d, move = "%s" }' % (row["level"], row["move"]) for row in rows
        )
        lines.append(f"  {species} = {{ {body} }},")
    out.write_text(
        "-- Generated by tools/export_cfru_learnsets.py from CFRU's Gen 6\n"
        "-- level-up tables.  Only the 18 new Fairy moves are listed; Charm,\n"
        "-- Moonlight and Sweet Kiss keep their native Gen 3 levels because\n"
        "-- main.lua merges this table into the ROM learnset.\n"
        "return {\n" + "\n".join(lines) + "\n}\n",
        encoding="utf-8",
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cfru", default=os.environ.get("CFRU_DIR"),
                        help="path to a Complete-Fire-Red-Upgrade checkout")
    parser.add_argument("--out", default="data/learnsets_fairy.lua",
                        help="output Lua file (default: data/learnsets_fairy.lua)")
    args = parser.parse_args()
    if not args.cfru:
        fail("pass --cfru <path> or set CFRU_DIR")
    root = Path(args.cfru).expanduser().resolve()
    species = parse_species(root)
    if len(species) < 350:
        fail(f"only {len(species)} Gen 3 species parsed; refusing a partial table")
    learnsets = parse_learnsets(root)
    filtered = {}
    for name, rows in learnsets.items():
        key = species.get(norm(name))
        if key:
            filtered[key] = rows
    if len(filtered) < 20:
        fail(f"only {len(filtered)} species with Fairy moves; refusing a partial table")
    emit(filtered, Path(args.out))
    moves = sorted({row["move"] for rows in filtered.values() for row in rows})
    print(f"wrote {args.out} ({len(filtered)} species, {len(moves)} moves)")
    print("moves: " + ", ".join(moves))


if __name__ == "__main__":
    main()
