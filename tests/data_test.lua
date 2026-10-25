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

print("data_test: ok")
