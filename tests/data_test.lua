local function load(rel)
  local chunk, err = loadfile(rel)
  assert(chunk, err)
  local ok, value = pcall(chunk)
  assert(ok, value)
  return value
end

local types = load("data/types.lua")
assert(type(types) == "table", "data/types.lua must return a table")
assert(types.index and types.index.FAIRY == 18, "Fairy must be index 18")
assert(types.names and types.names[18] == "FAIRY", "Fairy name missing")
assert(type(types.matchups) == "table", "matchups must be a table")
assert(types.complete == true, "the generated type chart must be complete")
assert(#types.matchups == 324, "expected 324 matchups, got " .. tostring(#types.matchups))

for _, row in ipairs(types.matchups) do
  assert(types.index[row.attacker], "unknown attacker type: " .. tostring(row.attacker))
  assert(types.index[row.defender], "unknown defender type: " .. tostring(row.defender))
  assert(row.multiplier == 0 or row.multiplier == 5 or row.multiplier == 10
    or row.multiplier == 20, "unexpected multiplier: " .. tostring(row.multiplier))
end

local species = load("data/species_fairy.lua")
local count = 0
for name, rows in pairs(species) do
  assert(type(name) == "string" and name ~= "", "species id must be a string")
  assert(type(rows) == "table" and #rows >= 1 and #rows <= 2,
    "species types must be a 1- or 2-element list: " .. name)
  for _, typeName in ipairs(rows) do
    assert(types.index[typeName], "unknown type " .. tostring(typeName) .. " for " .. name)
  end
  count = count + 1
end
assert(count == 18, "expected 18 Fairy species, got " .. tostring(count))

local changed = load("data/move_types_changed.lua")
assert(changed.CHARM == "FAIRY", "Charm must be Fairy")
assert(changed.MOONLIGHT == "FAIRY", "Moonlight must be Fairy")
assert(changed.SWEET_KISS == "FAIRY", "Sweet Kiss must be Fairy")
assert(changed.CURSE == "GHOST", "Curse must be Ghost")
for id, typeName in pairs(changed) do
  assert(types.index[typeName], "unknown changed-move type " .. tostring(typeName) .. " for " .. id)
end

local categories = load("data/move_categories.lua")
assert(type(categories) == "table", "move categories must be a table")
local categoryCount = 0
for id, value in pairs(categories) do
  assert(type(id) == "string" and id ~= "", "move category id must be a string")
  assert(value == "physical" or value == "special" or value == "status",
    "bad category " .. tostring(value) .. " for " .. id)
  categoryCount = categoryCount + 1
end
assert(categoryCount >= 350, "expected at least 350 move categories, got " .. categoryCount)

-- The engine's Gen 3 effect writer takes a string id, not the numeric
-- battle_move_effects.h value.  These are the names UnifiedEffects writes
-- back to their Gen 3 numbers; a typo here makes the engine silently refuse
-- the whole move at load time, so the list is pinned.
local EFFECT_NAMES = {
  NO_ADDITIONAL_EFFECT = true, SWIFT_EFFECT = true, DRAIN_HP_EFFECT = true,
  ATTACK_DOWN1_EFFECT = true, HEAL_EFFECT = true, SUPER_FANG_EFFECT = true,
  RECOIL_EFFECT = true, OVERHEAT = true, EXPLODE_EFFECT = true,
  ATTACK_DOWN_SIDE_EFFECT = true, SPECIAL_ATTACK_DOWN_HIT = true,
  CONFUSION_SIDE_EFFECT = true,
}

local moves = load("data/moves_fairy.lua")
assert(type(moves) == "table", "Fairy moves must be a table")
local moveCount = 0
for id, row in pairs(moves) do
  assert(type(id) == "string" and id ~= "", "Fairy move id must be a string")
  assert(type(row) == "table", "Fairy move must be a table: " .. id)
  assert(row.type == "FAIRY", "Fairy move type missing: " .. id)
  assert(type(row.index) == "number" and row.index >= 355, "bad Fairy move index: " .. id)
  assert(type(row.power) == "number" and type(row.accuracy) == "number"
    and type(row.pp) == "number", "bad Fairy move stats: " .. id)
  assert(row.category == nil, "category must stay in move_categories.lua: " .. id)
  assert(type(row.effect) == "string", "effect must be a string id: " .. id)
  assert(EFFECT_NAMES[row.effect], "unknown Gen 3 effect " .. tostring(row.effect) .. " for " .. id)
  assert(categories[id], "missing move category for " .. id)
  if row.secondaryChance ~= nil then
    assert(type(row.secondaryChance) == "number"
      and row.secondaryChance >= 0 and row.secondaryChance <= 100,
      "bad secondaryChance: " .. id)
  end
  moveCount = moveCount + 1
end
assert(moveCount >= 15, "expected at least 15 Fairy moves, got " .. moveCount)
assert(moves.PLAY_ROUGH and moves.PLAY_ROUGH.power == 90, "Play Rough missing")
assert(moves.MOONBLAST and moves.MOONBLAST.power == 95, "Moonblast missing")
assert(categories.PLAY_ROUGH == "physical", "Play Rough must be physical")
assert(categories.MOONBLAST == "special", "Moonblast must be special")
assert(categories.CHARM == "status", "Charm must be status")

local learnsets = load("data/learnsets_fairy.lua")
assert(type(learnsets) == "table", "Fairy learnsets must be a table")
local learnCount = 0
for species, rows in pairs(learnsets) do
  assert(type(species) == "string" and species ~= "", "learnset species must be a string")
  assert(type(rows) == "table" and #rows > 0, "learnset rows missing for " .. species)
  for _, row in ipairs(rows) do
    assert(type(row.level) == "number" and type(row.move) == "string",
      "bad learnset row for " .. species)
  end
  learnCount = learnCount + 1
end
assert(learnCount >= 10, "expected at least 10 species learnsets, got " .. learnCount)
assert(learnsets.CLEFAIRY and learnsets.GARDEVOIR and learnsets.MARILL,
  "expected Clefairy, Gardevoir and Marill learnsets")

-- Every learnset row has to name a move the mod actually ships (a new Fairy
-- move, or one of the native moves it re-types).
local known = { CHARM = true, MOONLIGHT = true, SWEET_KISS = true }
for id in pairs(moves) do known[id] = true end
for species, rows in pairs(learnsets) do
  local lastLevel = 0
  for _, row in ipairs(rows) do
    assert(known[row.move], "learnset for " .. species .. " names unknown move " .. tostring(row.move))
    assert(row.level >= 1 and row.level <= 100, "bad learnset level for " .. species)
    assert(row.level >= lastLevel, "learnset rows must be sorted for " .. species)
    lastLevel = row.level
  end
end

print("data_test: ok")
