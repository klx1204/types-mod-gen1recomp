-- Engine-side checks that need the fork but no ROM.
--
-- The mod's move records carry a *string* effect id because the Gen 3
-- content writer (UnifiedEffects.write) maps it back to the numeric
-- battle_move_effects.h value.  A name it does not round-trip is rejected
-- silently: the engine returns "unsupported: ..." and the loader keeps
-- going, so the mod would load with 18 missing moves.  This test pins the
-- mapping and the registration order that makes it work.
local engine = os.getenv("ENGINE_DIR")
if not engine or engine == "" then
  print("engine_effect_test: skipped (ENGINE_DIR is not set)")
  return
end

local function exists(path)
  local f = io.open(path, "rb")
  if not f then return false end
  f:close()
  return true
end

assert(exists(engine .. "/src/mods/UnifiedEffects.lua"), "ENGINE_DIR is not a gen1recomp checkout")
package.path = engine .. "/?.lua;" .. engine .. "/?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local Effects = require("src.mods.UnifiedEffects")
local moves = assert(loadfile("data/moves_fairy.lua"))()

-- effect name -> battle_move_effects.h numeric id
local EXPECT = {
  NO_ADDITIONAL_EFFECT = 0,
  SWIFT_EFFECT = 17,
  DRAIN_HP_EFFECT = 3,
  ATTACK_DOWN1_EFFECT = 18,
  HEAL_EFFECT = 32,
  SUPER_FANG_EFFECT = 40,
  RECOIL_EFFECT = 48,
  OVERHEAT = 204,
  EXPLODE_EFFECT = 7,
  ATTACK_DOWN_SIDE_EFFECT = 68,
  SPECIAL_ATTACK_DOWN_HIT = 71,
  CONFUSION_SIDE_EFFECT = 76,
}

local count = 0
for id, row in pairs(moves) do
  assert(type(row.effect) == "string", id .. ": effect must be a string id")
  local want = EXPECT[row.effect]
  assert(want ~= nil, id .. ": unpinned effect " .. tostring(row.effect))
  local native, _, reason = Effects.write(row.effect, 3, nil, function() return false end)
  assert(native == want, string.format(
    "%s: %s should write effect %d, got %s (%s)",
    id, row.effect, want, tostring(native), tostring(reason)))
  count = count + 1
end
assert(count >= 15, "expected the full Fairy move set, got " .. count)

-- The move writer validates a move's type against the type_chart registry,
-- so FAIRY must be registered before any move that uses it.
local src = assert(io.open("main.lua", "rb")):read("*a")
local chart = src:find('type_chart:register("FAIRY"', 1, true)
local move = src:find("moves:register(id, record)", 1, true)
assert(chart ~= nil, "main.lua must register the FAIRY type")
assert(move ~= nil, "main.lua must register the Fairy moves")
assert(chart < move, "FAIRY has to be in type_chart before the moves are registered")

print("engine_effect_test: ok (" .. count .. " moves)")
