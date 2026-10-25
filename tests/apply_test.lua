-- Apply/VANILLA round-trip with stubbed engine tables. No ROM, no LÖVE.
local root = "."

local function readFile(rel)
  local f = io.open(root .. "/" .. rel, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function loadData(name)
  local chunk = assert(loadfile(root .. "/data/" .. name .. ".lua"))
  return chunk()
end

local species = loadData("species_fairy")
local speciesIds = {}
local nextId = 100
for name in pairs(species) do
  speciesIds[name] = nextId
  nextId = nextId + 1
end

local moveNames = { "CHARM", "MOONLIGHT", "SWEET_KISS", "CURSE", "MOONBLAST" }
local moveIds = { CHARM = 204, MOONLIGHT = 236, SWEET_KISS = 186, CURSE = 174, MOONBLAST = 362 }
local moveIdByName = {}
local nameById = {}
for _, name in ipairs(moveNames) do
  local id = moveIds[name]
  moveIdByName[name] = id
  nameById[id] = name
end

local function row(typeNum)
  return { type = typeNum, power = 0, category = "status" }
end
local rom = {
  [204] = row(0), [236] = row(0), [186] = row(0), [174] = row(9),
}
local link = {
  [204] = row(0), [236] = row(0), [186] = row(0), [174] = row(9),
}
local battle = {
  [204] = row(0), [236] = row(0), [186] = row(0), [174] = row(9),
}
local dataMoves = {
  CHARM = { type = "NORMAL" },
  MOONLIGHT = { type = "NORMAL" },
  SWEET_KISS = { type = "NORMAL" },
  CURSE = { type = "CURSE_TYPE" },
}

local overlay, cleared = nil, false
local Types = {
  MOVE_CATEGORY = true,
  isPhysical = function(typeNum) return typeNum <= 8 end,
  effectiveness = function() return 1 end,
  name = function(id) return tostring(id) end,
  useOverlay = function(value) overlay = value end,
  clearOverlay = function() cleared = true end,
}
package.loaded["src.core.game3.battle.types"] = nil
package.preload["src.core.game3.battle.types"] = function() return Types end

local Moves = {
  _rom = rom,
  _linkRows = link,
  romReady = function() end,
  numForName = function(name) return moveIdByName[name] end,
  constName = function(id) return nameById[id] end,
}
package.preload["src.core.game3.battle.moves"] = function() return Moves end

local Pokemon = {
  _types = {},
  _learnsets = {},
  _battleMoves = battle,
  types = function(id) return Pokemon._types[id] or { 0, 0 } end,
  battleMove = function(id) return Pokemon._battleMoves[id] end,
  speciesFromName = function(name) return speciesIds[name] end,
}
package.preload["src.core.game3.pokemon"] = function() return Pokemon end
package.preload["src.core.game3.runtime"] = function()
  return { _game = { data = { moves = dataMoves } } }
end

local hooks, events, store = {}, {}, {}
local mod = {
  path = root,
  log = { info = function() end, warn = function() end, error = function() end },
  save = {
    get = function(_, key, default) return store[key] ~= nil and store[key] or default end,
    set = function(_, key, value) store[key] = value end,
  },
  hooks = { wrap = function(_, name, fn) hooks[name] = fn end },
  events = { on = function(_, name, fn) events[name] = fn end },
  content = { moves = { register = function() end } },
  ui = {},
}
function mod:read(rel) return readFile(rel) end

local entry = assert(loadfile(root .. "/main.lua"))()
entry(mod)

local rows = hooks["ui.options.rows"](function(_, value) return value end, {}, {})
local battleRow
for _, row in ipairs(rows) do
  if row.id == "gen9_battle_data" then battleRow = row end
end
assert(battleRow, "BATTLE DATA row missing")

assert(battleRow.value() == "VANILLA", "initial mode must be VANILLA")
assert(battleRow.step({}) == true, "VANILLA -> GEN9 should apply")
assert(overlay ~= nil, "Types.useOverlay not called")
assert(Pokemon._types[speciesIds.CLEFAIRY] ~= nil, "species type not applied")
assert(Pokemon._types[speciesIds.CLEFAIRY][1] == 18, "Clefairy must be Fairy")
assert(rom[204].type == 18, "Moves._rom Charm type not applied")
assert(link[204].type == 18, "Moves._linkRows Charm type not applied")
assert(battle[204].type == 18, "Pokemon._battleMoves Charm type not applied")
assert(dataMoves.CHARM.type == "FAIRY", "data.moves Charm type not applied")
assert(rom[174].type == 7, "Curse must become Ghost")
local clefairyLearn = Pokemon._learnsets[speciesIds.CLEFAIRY] or {}
local hasMoonblast = false
for _, row in ipairs(clefairyLearn) do
  if row.move == 362 and row.level == 44 then hasMoonblast = true end
end
assert(hasMoonblast, "Clefairy Moonblast was not resolved to a numeric id")

assert(battleRow.step({}) == true, "GEN9 -> VANILLA should restore")
assert(cleared == true, "Types.clearOverlay not called")
assert(rom[204].type == 0, "Charm type not restored")
assert(link[204].type == 0, "Charm link type not restored")
assert(battle[204].type == 0, "Charm battle type not restored")
assert(dataMoves.CHARM.type == "NORMAL", "Charm data type not restored")
assert(rom[174].type == 9, "Curse type not restored")
assert(#(Pokemon._learnsets[speciesIds.CLEFAIRY] or {}) == 0,
  "Clefairy learnset not restored")

package.loaded["src.core.game3.battle.init"] = { _active = true }
assert(battleRow.step({}) == false, "battle must refuse the switch")
assert(battleRow.value() == "VANILLA", "battle refusal must keep the mode")

print("apply_test: ok")
