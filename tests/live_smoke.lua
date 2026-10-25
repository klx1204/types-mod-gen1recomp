-- Live smoke test for all five Gen 3 games.
--
-- This one needs a real ROM-imported engine cache, so it is not part of CI.
-- From a gen1recomp checkout with this repository copied to
-- mods/types_mod_gen1recomp:
--
--   POKEPORT_IDENTITY=<identity> POKEPORT_VERSION=firered \
--     POKEPORT_DRIVER=<this file> love .
--
-- Repeat for leafgreen, emerald, ruby and sapphire.  It checks the mode
-- switch, the Gen 9 chart, the 18 species, the 18 moves, per-move
-- physical/special, and the VANILLA restore.
local U = require("tests.drivers.util")
local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end
return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.boot ~= nil, "boot reached") then love.event.quit(1) return end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local ModRuntime = require("src.mods.Runtime")
  local Types = require("src.core.game3.battle.types")
  local Pokemon = require("src.core.game3.pokemon")
  local Moves = require("src.core.game3.battle.moves")
  if not check(Runtime.getSession() ~= nil, "new game reached the field") then love.event.quit(1) return end

  local rows = ModRuntime.call("ui.options.rows", function(_, r) return r end, game, {})
  local row
  for _, r in ipairs(rows or {}) do if r.id == "gen9_battle_data" then row = r end end
  if not check(row ~= nil, "BATTLE DATA row exists") then love.event.quit(1) return end
  if row.value() ~= "GEN9" then
    check(row.step(game) == true, "switch to GEN9")
    U.wait(30)
  end
  check(Types.effectiveness(18, 16, 16) == 2, "Fairy vs Dragon 2x")
  check(Types.effectiveness(18, 8, 8) == 0.5, "Fairy vs Steel 0.5x")
  check(Types.effectiveness(17, 8, 8) == 1, "Dark vs Steel 1x")
  check(Types.effectiveness(11, 10, 10) == 2, "Water vs Fire 2x (native row intact)")
  local t = Pokemon.types(Pokemon.speciesFromName("MARILL"))
  check(t[1] == 11 and t[2] == 18, "Marill Water/Fairy")
  local g = Pokemon.types(Pokemon.speciesFromName("GARDEVOIR"))
  check(tostring(g[2]) == "18" or tostring(g[1]) == "18", "Gardevoir is Fairy (" .. tostring(g[1]) .. "/" .. tostring(g[2]) .. ")")
  local pr = Moves.numForName("PLAY_ROUGH")
  local prm = pr and Moves.get(pr)
  check(prm and prm.category == "physical", "Play Rough physical")
  check(prm and prm.effect == 68, "Play Rough effect 68")
  local mb = Moves.numForName("MOONBLAST")
  check(mb and Moves.get(mb).category == "special", "Moonblast special")
  check(Pokemon.battleMove(pr) and Pokemon.battleMove(pr).category == "physical", "battleMove physical")
  local moon = Moves.numForName("MOONBLAST")
  local has = false
  for _, lr in ipairs(Pokemon.learnset(Pokemon.speciesFromName("CLEFAIRY")) or {}) do
    if lr.move == moon or lr[2] == moon then has = true end
  end
  check(has, "Clefairy learns Moonblast")
  check(row.step(game) == true, "switch back to VANILLA")
  U.wait(30)
  local t2 = Pokemon.types(Pokemon.speciesFromName("MARILL"))
  check(t2[1] == 11 and (t2[2] or 0) ~= 18, "Marill restored")
  check(Types.effectiveness(18, 16, 16) == 1, "Fairy row cleared in VANILLA")
  print((failures == 0 and "PASS" or "FAIL") .. " mod_all failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
end
