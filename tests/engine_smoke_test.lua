-- Optional engine smoke test. It never requires a ROM and skips cleanly when
-- ENGINE_DIR is not set, so `luajit tests/engine_smoke_test.lua` works in any
-- checkout.
local engine = os.getenv("ENGINE_DIR")
if not engine or engine == "" then
  print("engine_smoke_test: skipped (ENGINE_DIR is not set)")
  return
end

local function exists(path)
  local f = io.open(path, "rb")
  if not f then return false end
  f:close()
  return true
end

assert(exists(engine .. "/main.lua"), "ENGINE_DIR does not look like a gen1recomp checkout")
assert(exists(engine .. "/src/core/game3/battle/damage.lua"), "engine is missing the Gen 3 battle module")

-- The fork is expected to expose the per-move category entry point. The
-- official engine does not, so report it rather than failing.
local full = exists(engine .. "/src/core/game3/battle/phy_spc.lua")
print("engine_smoke_test: ok (" .. (full and "full" or "compat") .. " mode)")
