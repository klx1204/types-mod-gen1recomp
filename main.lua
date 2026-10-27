-- Gen 9 Types & Battle Data for gen1recomp
--
-- Entry point. The mod is deliberately defensive: on the official engine it
-- runs in compat mode (no `Types.MOVE_CATEGORY`), and it never applies a
-- half-generated type chart. See AGENTS.md for the rules.

local function readData(mod, name)
  local rel = "data/" .. name .. ".lua"
  local src, readErr = mod:read(rel)
  if not src then return nil, readErr or (rel .. " missing") end
  local chunk, compileErr = load(src, "@" .. mod.path .. "/" .. rel, "t", {})
  if not chunk then return nil, compileErr end
  local ok, value = pcall(chunk)
  if not ok then return nil, value end
  return value
end

local function deepcopy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for key, item in pairs(value) do out[key] = deepcopy(item) end
  return out
end

local function battleActive()
  local Battle = package.loaded["src.core.game3.battle.init"]
  return Battle ~= nil and Battle._active == true
end

local function speciesId(Pokemon, name)
  if type(name) ~= "string" then return tonumber(name) end
  if Pokemon.speciesFromName then
    local id = Pokemon.speciesFromName(name)
    if id then return id end
  end
  if Pokemon._byName and Pokemon._byName[name] then return Pokemon._byName[name] end
  return tonumber(name)
end

local function moveId(Moves, name)
  if type(name) == "number" then return name end
  if Moves.numForName then return Moves.numForName(name) end
  return tonumber(name)
end

local function currentGame()
  local Runtime = package.loaded["src.core.game3.runtime"]
  if not Runtime then
    local ok, loaded = pcall(require, "src.core.game3.runtime")
    if ok then Runtime = loaded end
  end
  return Runtime and Runtime._game or nil
end

local function gameData()
  local game = currentGame()
  return game and game.data or nil
end

local function moveKey(Moves, id, name)
  local const = Moves.constName and Moves.constName(id)
  return const or name or id
end

local function moveRows(Moves, Pokemon, Data, id, name)
  local key = moveKey(Moves, id, name)
  local rom = Moves._rom and Moves._rom[id]
  local linked = Moves._linkRows and Moves._linkRows[id]
  local battle = Pokemon and Pokemon._battleMoves and Pokemon._battleMoves[id]
  local dataRow = Data and Data.moves
    and (Data.moves[key] or Data.moves["MOVE_" .. tostring(key)]
      or Data.moves[name] or Data.moves[id])
  return rom, linked, battle, dataRow
end

return function(mod)
  local Types = require("src.core.game3.battle.types")
  local FULL = type(rawget(Types, "MOVE_CATEGORY")) == "boolean"

  -- The Fairy name has to survive clearOverlay(): a saved Pokémon can still
  -- reference type 18 after switching to VANILLA, and a link battle may
  -- rebuild the chart behind the mod's back.  Without this the ROM lookup
  -- runs past the end of gTypeNames and Emerald shows the first contest
  -- category ("COOL") as the second type.
  if type(Types.CUSTOM_NAMES) == "table" then
    Types.CUSTOM_NAMES[18] = "FAIRY"
  end
  -- Optional 32x16 badge; menus fall back to the name if it cannot load.
  if type(Types.CUSTOM_ICONS) == "table" and type(mod.path) == "string" then
    Types.CUSTOM_ICONS[18] = mod.path .. "/assets/type_icons/fairy.png"
  end

  local data = {}
  for _, name in ipairs({
    "types",
    "species_fairy",
    "move_types_changed",
    "move_categories",
    "moves_fairy",
    "learnsets_fairy",
    "zh_names",
  }) do
    local value, err = readData(mod, name)
    if value == nil then
      mod.log:warn("data/%s.lua: %s", name, tostring(err))
      value = {}
    end
    data[name] = value
  end

  local current = "GEN9"
  do
    local ok, saved = pcall(function() return mod.save:get("mode", "GEN9") end)
    if ok and (saved == "GEN9" or saved == "VANILLA") then current = saved end
  end
  if current == "GEN9" and not data.types.complete then
    mod.log:warn("Gen 9 data is incomplete; staying in VANILLA")
    current = "VANILLA"
  end

  -- Chinese names: a CJK TTF covers only CJK codepoints, so the rest of the
  -- UI keeps the ROM atlas.  The table is optional; without it the mod runs
  -- with English names.
  local function applyZhNames()
    local zh = data.zh_names
    if type(zh) ~= "table" then return end
    local okP, Pokemon = pcall(require, "src.core.game3.pokemon")
    local okM, Moves = pcall(require, "src.core.game3.battle.moves")
    if not (okP and Pokemon and Pokemon._names) then return end
    -- Keep the English ROM names so a nickname that still matches the
    -- species name can be shown in Chinese.
    if not Pokemon._zhRomNames then
      Pokemon._zhRomNames = {}
      for id, name in pairs(Pokemon._names) do Pokemon._zhRomNames[id] = name end
    end
    for name, text in pairs(zh.species or {}) do
      local id = Pokemon.speciesFromName and Pokemon.speciesFromName(name)
      if id then Pokemon._names[id] = text end
    end
    if okM and Moves and Pokemon._moveNames then
      for name, text in pairs(zh.moves or {}) do
        local id = Moves.numForName and Moves.numForName(name)
        if id then Pokemon._moveNames[id] = text end
      end
    end
    local function localized(mon, name)
      local species = mon and ((Pokemon.speciesOf and Pokemon.speciesOf(mon)) or mon.species)
      local zhName = species and Pokemon._names[species]
      local romName = species and Pokemon._zhRomNames[species]
      if zhName and romName and name == romName then return zhName end
      return name
    end
    if Pokemon.displayName and not Pokemon._zhDisplayWrapped then
      Pokemon._zhDisplayWrapped = true
      local original = Pokemon.displayName
      Pokemon.displayName = function(mon)
        return localized(mon, original(mon))
      end
    end
    local okS, State = pcall(require, "src.core.game3.battle.state")
    if okS and State and State.displayName and not State._zhWrapped then
      State._zhWrapped = true
      local original = State.displayName
      State.displayName = function(battler)
        return localized(battler and battler.mon, original(battler))
      end
    end
  end

  if type(data.zh_names) == "table" then
    applyZhNames()
  end

  local baseline

  local function capture()
    if baseline then return true end
    local okP, Pokemon = pcall(require, "src.core.game3.pokemon")
    local okM, Moves = pcall(require, "src.core.game3.battle.moves")
    if not okP or not Pokemon or not okM or not Moves then
      return false, "engine modules unavailable"
    end
    -- Force the lazy loaders before snapshotting.
    pcall(Pokemon.types, 1)
    pcall(Pokemon.battleMove, 1)
    pcall(Moves.romReady)

    local Data = gameData()
    baseline = {
      types = deepcopy(Pokemon._types or {}),
      learnsets = {},
      moveTypes = {},
      battleTypes = {},
      dataTypes = {},
      categories = {},
      battleCategories = {},
    }

    for name in pairs(data.species_fairy or {}) do
      local id = speciesId(Pokemon, name)
      if id then
        baseline.learnsets[id] = deepcopy(Pokemon._learnsets and Pokemon._learnsets[id] or {})
      end
    end

    for name in pairs(data.move_types_changed or {}) do
      local id = moveId(Moves, name)
      if id then
        local rom, linked, battle, dataRow = moveRows(Moves, Pokemon, Data, id, name)
        if rom then baseline.moveTypes[id] = rom.type end
        if battle then baseline.battleTypes[id] = battle.type end
        if dataRow then baseline.dataTypes[id] = dataRow.type end
      end
    end

    for name in pairs(data.move_categories or {}) do
      local id = moveId(Moves, name)
      if id then
        local rom, linked, battle = moveRows(Moves, Pokemon, Data, id, name)
        if rom then baseline.categories[id] = rom.category end
        if battle then baseline.battleCategories[id] = battle.category end
      end
    end

    return true
  end

  local function flatChart()
    local flat = {}
    local index = data.types.index or {}
    for _, row in ipairs(data.types.matchups or {}) do
      local attacker = index[row.attacker]
      local defender = index[row.defender]
      if attacker and defender then
        flat[#flat + 1] = attacker
        flat[#flat + 1] = defender
        flat[#flat + 1] = row.multiplier
      end
    end
    flat[#flat + 1] = -1
    flat[#flat + 1] = -1
    flat[#flat + 1] = 0
    return flat
  end

  local function applySpeciesTypes(enable, Pokemon)
    if not Pokemon then return end
    if not enable then
      Pokemon._types = deepcopy(baseline.types)
      return
    end
    local index = data.types.index or {}
    for name, types in pairs(data.species_fairy or {}) do
      local id = speciesId(Pokemon, name)
      if id then
        local numbers = {}
        for i, typeName in ipairs(types) do
          numbers[i] = index[typeName] or 0
        end
        Pokemon._types = Pokemon._types or {}
        Pokemon._types[id] = numbers
      end
    end
  end

  local function applyLearnsets(enable, Pokemon, Moves)
    if not Pokemon then return end
    if not enable then
      for id, rows in pairs(baseline.learnsets) do
        Pokemon._learnsets[id] = deepcopy(rows)
      end
      return
    end
    for name, rows in pairs(data.learnsets_fairy or {}) do
      local id = speciesId(Pokemon, name)
      if id then
        local merged = deepcopy(Pokemon._learnsets and Pokemon._learnsets[id] or {})
        local seen = {}
        for _, row in ipairs(merged) do
          seen[tostring(row.level) .. ":" .. tostring(row.move)] = true
        end
        for _, row in ipairs(rows) do
          local moveId = row.move
          if Moves and Moves.numForName and type(moveId) == "string" then
            moveId = Moves.numForName(moveId)
          end
          if moveId then
            local key = tostring(row.level) .. ":" .. tostring(moveId)
            if not seen[key] then
              merged[#merged + 1] = { level = row.level, move = moveId }
              seen[key] = true
            end
          end
        end
        table.sort(merged, function(a, b)
          if (a.level or 0) == (b.level or 0) then
            return tostring(a.move) < tostring(b.move)
          end
          return (a.level or 0) < (b.level or 0)
        end)
        Pokemon._learnsets = Pokemon._learnsets or {}
        Pokemon._learnsets[id] = merged
      end
    end
  end

  local function applyMoveTypes(enable, Moves, Pokemon, Data)
    if not Moves then return end
    local index = data.types.index or {}
    if not enable then
      for id, typeNum in pairs(baseline.moveTypes) do
        local rom, linked, battle = moveRows(Moves, Pokemon, Data, id)
        if rom then rom.type = typeNum end
        if linked then linked.type = typeNum end
        if battle then battle.type = typeNum end
      end
      for id, typeName in pairs(baseline.dataTypes) do
        local _, _, _, dataRow = moveRows(Moves, Pokemon, Data, id)
        if dataRow then dataRow.type = typeName end
      end
      return
    end
    for name, typeName in pairs(data.move_types_changed or {}) do
      local id = moveId(Moves, name)
      local typeNum = index[typeName]
      if id and typeNum then
        local rom, linked, battle, dataRow = moveRows(Moves, Pokemon, Data, id, name)
        if rom then rom.type = typeNum end
        if linked then linked.type = typeNum end
        if battle then battle.type = typeNum end
        if dataRow then dataRow.type = typeName end
      end
    end
  end

  local function applyCategories(enable, Moves, Pokemon, Data)
    if not FULL or not Moves then return end
    if not enable then
      for id, category in pairs(baseline.categories) do
        local rom, linked, battle = moveRows(Moves, Pokemon, Data, id)
        if rom then rom.category = category end
        if linked then linked.category = category end
        if battle then battle.category = category end
      end
      return
    end
    for name, category in pairs(data.move_categories or {}) do
      local id = moveId(Moves, name)
      if id then
        local rom, linked, battle = moveRows(Moves, Pokemon, Data, id, name)
        if rom then rom.category = category end
        if linked then linked.category = category end
        if battle then battle.category = category end
      end
    end
  end

  local function invalidate()
    pcall(function() require("src.ui.game3.chrome").invalidate() end)
  end

  local function apply(mode, force)
    if mode ~= "GEN9" and mode ~= "VANILLA" then
      return false, "unknown mode"
    end
    if mode == current and not force then return true end
    if battleActive() then return false, "battle" end
    if mode == "GEN9" and not data.types.complete then
      return false, "data incomplete"
    end

    local ok, why = capture()
    if not ok then return false, why end

    local okP, Pokemon = pcall(require, "src.core.game3.pokemon")
    local okM, Moves = pcall(require, "src.core.game3.battle.moves")
    if not okP then Pokemon = nil end
    if not okM then Moves = nil end
    local Data = gameData()

    if mode == "GEN9" then
      Types.useOverlay({
        table = flatChart(),
        physical = data.types.physical or {},
        names = data.types.names or {},
      })
      applySpeciesTypes(true, Pokemon)
      applyLearnsets(true, Pokemon, Moves)
      applyMoveTypes(true, Moves, Pokemon, Data)
      applyCategories(true, Moves, Pokemon, Data)
    else
      Types.clearOverlay()
      applySpeciesTypes(false, Pokemon)
      applyLearnsets(false, Pokemon, Moves)
      applyMoveTypes(false, Moves, Pokemon, Data)
      applyCategories(false, Moves, Pokemon, Data)
    end

    current = mode
    pcall(function() mod.save:set("mode", mode) end)
    invalidate()
    return true
  end

  local function notify(game, text)
    if game and mod.ui and mod.ui.TextBox then
      local ok = pcall(function() mod.ui.TextBox.new(game, text, nil) end)
      if ok then return end
    end
    mod.log:warn("%s", text)
  end

  local function toggleMode(game)
    local target = current == "GEN9" and "VANILLA" or "GEN9"
    local ok, why = apply(target)
    if not ok then
      if why == "battle" then
        notify(game, "BATTLE DATA cannot change during battle.")
      elseif why == "data incomplete" then
        notify(game, "Gen 9 data is incomplete. Run the data exporter first.")
      else
        notify(game, "BATTLE DATA switch failed: " .. tostring(why))
      end
      return false
    end
    return true
  end

  local function flag(key)
    local ok, value = pcall(function() return mod.save:get(key, false) end)
    return ok and value == true
  end

  local function setFlag(key, value)
    pcall(function() mod.save:set(key, value) end)
  end

  local function toggleFlag(key)
    local value = not flag(key)
    setFlag(key, value)
    return value
  end

  -- Multi-value rows (WILD ENCOUNTERS, SHINY ODDS) store their index, so the
  -- saved value survives a table reorder only if the order is kept.
  local function choice(key, values)
    local ok, stored = pcall(function() return mod.save:get(key, 1) end)
    local index = ok and tonumber(stored) or 1
    if not index or index < 1 or index > #values then index = 1 end
    return index
  end

  local function cycleChoice(key, values)
    local index = choice(key, values) % #values + 1
    pcall(function() mod.save:set(key, index) end)
    return index
  end

  -- The engine validates a move's type against the type_chart registry while
  -- the move is written, so FAIRY has to exist there before the moves below
  -- are registered.  Registering the chart also teaches the engine's custom
  -- type table that index 18 is FAIRY, which the move writer needs.
  if data.types and data.types.complete then
    local ok, err = pcall(function()
      mod.content.type_chart:register("FAIRY", {
        index = data.types.fairyIndex or 18,
        name = "FAIRY",
        category = "special",
      })
    end)
    if not ok then
      mod.log:warn("could not register the FAIRY type: %s", tostring(err))
    end
    local failed = 0
    for _, row in ipairs(data.types.matchups or {}) do
      local a, d = row.attacker, row.defender
      if a and d then
        local okRow, rowErr = pcall(function()
          -- override, not register: the engine seeds the native 17x17 chart
          -- and Gen 9 changes several of those native rows.
          mod.content.type_chart:override(a .. ">" .. d, {
            multiplier = row.multiplier,
          })
        end)
        if not okRow then
          failed = failed + 1
          if failed <= 3 then
            mod.log:warn("could not register %s>%s: %s", a, d, tostring(rowErr))
          end
        end
      end
    end
    if failed > 0 then
      mod.log:warn("%d Gen 9 matchups were rejected", failed)
    end
  end

  -- Entry-time registrations: content registries freeze after this chunk.
  for id, record in pairs(data.moves_fairy or {}) do
    local ok, err = pcall(function()
      mod.content.moves:register(id, record)
    end)
    if not ok then
      mod.log:warn("could not register move %s: %s", tostring(id), tostring(err))
    end
  end

  -- Options rows. The data mode row refuses changes in battle.
  mod.hooks:wrap("ui.options.rows", function(next, game, rows)
    local out = next(game, rows)
    if type(out) ~= "table" then return out end

    out[#out + 1] = {
      id = "gen9_battle_data",
      label = "BATTLE DATA",
      value = function() return current end,
      step = function(game) return toggleMode(game) end,
    }

    local function toggleRow(id, label, key)
      out[#out + 1] = {
        id = id,
        label = label,
        value = function() return flag(key) and "ON" or "OFF" end,
        step = function() return toggleFlag(key) end,
      }
    end

    local function cycleRow(id, label, key, values)
      out[#out + 1] = {
        id = id,
        label = label,
        value = function() return values[choice(key, values)] end,
        step = function() return cycleChoice(key, values) end,
      }
    end

    toggleRow("gen9_exp_catch", "EXP FOR CATCHING", "exp_catch")
    toggleRow("gen9_exp_share", "PARTY EXP SHARE", "exp_share")
    toggleRow("gen9_field_hms", "HMs WITHOUT MOVE", "field_hms")
    toggleRow("gen9_infinite_tms", "INFINITE TMS", "infinite_tms")
    toggleRow("gen9_trade_evo", "TRADE EVO LV. 40", "trade_evo")
    toggleRow("gen9_always_catch", "ALWAYS CATCH", "always_catch")
    cycleRow("gen9_encounter_rate", "WILD ENCOUNTERS", "encounter_rate",
      { "NORMAL", "OFF", "1/4", "1/2", "2X" })
    cycleRow("gen9_shiny_odds", "SHINY ODDS", "shiny_odds",
      { "1/8192", "1/4096", "1/1024", "1/256", "1/64", "ALWAYS" })
    return out
  end)

  -- EXP for catching.
  mod.hooks:wrap("battle.catch_exp", function(next, ctx)
    if flag("exp_catch") then return true end
    return next(ctx)
  end)

  -- Party EXP Share: award every healthy party member through applyShare.
  mod.hooks:wrap("battle.exp_award", function(next, ctx)
    if not flag("exp_share") then return next(ctx) end
    for _, mon in ipairs(ctx.alive or {}) do
      if type(ctx.applyShare) == "function" then ctx.applyShare(mon, 1) end
    end
  end)

  -- HMs without knowing the move: any healthy party member can act as the user.
  mod.hooks:wrap("fieldmove.eligibility", function(next, moveIdValue, ctx)
    if not flag("field_hms") then return next(moveIdValue, ctx) end
    for _, mon in ipairs((ctx and ctx.party) or {}) do
      if not mon.isEgg and not mon.egg and (tonumber(mon.hp) or 0) > 0 then
        return mon
      end
    end
    return next(moveIdValue, ctx)
  end)

  -- Infinite TMs: let the native flow run, then put the TM back.
  mod.hooks:wrap("item.use", function(next, game, kind, id, partySlot, bag)
    local ok, resultKind, text = next(game, kind, id, partySlot, bag)
    if flag("infinite_tms") and ok and resultKind == "tm" then
      pcall(function()
        local ItemsData = require("src.core.game3.items_data")
        if not ItemsData.isHm(id) then
          require("src.core.game3.bag").add(bag, id, 1)
        end
      end)
    end
    return ok, resultKind, text
  end)

  -- Trade evolutions at Lv. 40 (emerald-3ds-fairy 0012).  A trade evolution
  -- happens on reaching the level; an item trade evolution still needs its
  -- item, which is used up afterwards, as a real trade would.
  local tradeEvoPending = setmetatable({}, { __mode = "k" })
  mod.hooks:wrap("evolution.check", function(next, game, mon, view, trigger)
    local matched = next(game, mon, view, trigger)
    if matched then return true end
    if not flag("trade_evo") or not mon then return false end
    if not (trigger and trigger.kind == "levelup") then return false end
    local method = view and view.method
    if method ~= "EVO_TRADE" and method ~= "EVO_TRADE_ITEM" then return false end
    if (tonumber(mon.level) or 0) < 40 then return false end
    if method == "EVO_TRADE_ITEM" then
      local held = tonumber(mon.item or mon.heldItem) or 0
      if held == 0 or held ~= tonumber(view.param) then return false end
      tradeEvoPending[mon] = true
    end
    return true
  end)

  mod.events:on("pokemon.evolved", function(e)
    local mon = e and e.mon
    if not (mon and tradeEvoPending[mon]) then return end
    tradeEvoPending[mon] = nil
    mon.item, mon.heldItem = 0, 0
    if mon.heldItemId ~= nil then mon.heldItemId = 0 end
  end)

  -- Always catch: skip the shake roll entirely.
  mod.hooks:wrap("catch.rate", function(next, ball, mon, species, opts)
    if flag("always_catch") then return true, 4 end
    return next(ball, mon, species, opts)
  end)

  -- Wild encounter rate (emerald-3ds-fairy 0021).  Walking and surfing only:
  -- the engine still routes fishing and set encounters elsewhere.
  local ENCOUNTER_RATES = { "NORMAL", "OFF", "1/4", "1/2", "2X" }
  mod.hooks:wrap("encounter.roll", function(next, tableForMap, ctx)
    local mode = ENCOUNTER_RATES[choice("encounter_rate", ENCOUNTER_RATES)]
    local enc = next(tableForMap, ctx)
    if mode == "OFF" then return nil end
    if not enc then
      -- 2X is one extra roll, which doubles p without changing it for a
      -- success that already happened.
      if mode == "2X" then return next(tableForMap, ctx) end
      return nil
    end
    local rng = (ctx and ctx.rng) or math.random
    local roll = function() return (rng() or 0) end
    if mode == "1/4" and roll() % 4 ~= 1 then return nil end
    if mode == "1/2" and roll() % 2 ~= 1 then return nil end
    return enc
  end)

  -- Shiny odds (emerald-3ds-fairy 0022); the first step is the native roll.
  local SHINY_ODDS = { "1/8192", "1/4096", "1/1024", "1/256", "1/64", "ALWAYS" }
  local SHINY_DENOM = { ["1/4096"] = 4096, ["1/1024"] = 1024, ["1/256"] = 256, ["1/64"] = 64 }
  local okRng, Rng = pcall(require, "src.core.game3.rng")
  local function shinyRoll(denom)
    if okRng and Rng and type(Rng.Random) == "function" then
      return Rng.Random() % denom == 0
    end
    return math.random(denom) == 1
  end
  mod.hooks:wrap("shiny.roll", function(next, ctx)
    local mode = SHINY_ODDS[choice("shiny_odds", SHINY_ODDS)]
    if mode == "ALWAYS" then return true end
    local denom = SHINY_DENOM[mode]
    if denom and shinyRoll(denom) then return true end
    if mode == "1/8192" then return next(ctx) end
    return false
  end)

  -- Apply the saved mode once the engine has a save and a dataset.  This  -- runs for VANILLA too: registering FAIRY in type_chart makes the loader
  -- install its Gen 9 overlay before the game boots, so a VANILLA save has
  -- to clear that overlay explicitly instead of assuming the engine is
  -- still pristine.
  local function restore()
    applyZhNames()
    local ok, why
    if current == "GEN9" then
      ok, why = apply("GEN9", true)
    else
      ok, why = apply("VANILLA", true)
    end
    if not ok then
      mod.log:warn("could not apply %s data: %s", current, tostring(why))
    end
  end

  if mod.events and mod.events.on then
    mod.events:on("game.ready", restore)
    mod.events:on("save.loaded", restore)
  end

  if FULL then
    mod.log:info("per-move physical/special available")
  else
    mod.log:warn("official engine detected: per-move category is unavailable; Play Rough falls back to the type category")
  end
end
