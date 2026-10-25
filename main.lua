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

return function(mod)
  local Types = require("src.core.game3.battle.types")
  local FULL = type(rawget(Types, "MOVE_CATEGORY")) == "boolean"

  local data = {}
  for _, name in ipairs({
    "types",
    "species_fairy",
    "move_types_changed",
    "move_categories",
    "moves_fairy",
    "learnsets_fairy",
  }) do
    local value, err = readData(mod, name)
    if value == nil then
      mod.log:warn("data/%s.lua: %s", name, tostring(err))
      value = {}
    end
    data[name] = value
  end

  local current = "VANILLA"
  do
    local ok, saved = pcall(function() return mod.save:get("mode", "VANILLA") end)
    if ok and (saved == "GEN9" or saved == "VANILLA") then current = saved end
  end
  if current == "GEN9" and not data.types.complete then
    mod.log:warn("Gen 9 data is incomplete; staying in VANILLA")
    current = "VANILLA"
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
    pcall(Moves.romReady)

    baseline = {
      types = deepcopy(Pokemon._types or {}),
      learnsets = {},
      moveTypes = {},
      categories = {},
    }

    for name in pairs(data.species_fairy or {}) do
      local id = speciesId(Pokemon, name)
      if id then
        baseline.learnsets[id] = deepcopy(Pokemon._learnsets and Pokemon._learnsets[id] or {})
      end
    end

    for name in pairs(data.move_types_changed or {}) do
      local id = moveId(Moves, name)
      local row = id and Moves._rom and Moves._rom[id]
      if row then baseline.moveTypes[id] = row.type end
    end

    for name in pairs(data.move_categories or {}) do
      local id = moveId(Moves, name)
      local row = id and Moves._rom and Moves._rom[id]
      if row then baseline.categories[id] = row.category end
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

  local function applyLearnsets(enable, Pokemon)
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
          local key = tostring(row.level) .. ":" .. tostring(row.move)
          if not seen[key] then
            merged[#merged + 1] = { level = row.level, move = row.move }
            seen[key] = true
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

  local function applyMoveTypes(enable, Moves)
    if not Moves then return end
    local index = data.types.index or {}
    if not enable then
      for id, typeNum in pairs(baseline.moveTypes) do
        local row = Moves._rom and Moves._rom[id]
        if row then row.type = typeNum end
        local linked = Moves._linkRows and Moves._linkRows[id]
        if linked then linked.type = typeNum end
      end
      return
    end
    for name, typeName in pairs(data.move_types_changed or {}) do
      local id = moveId(Moves, name)
      local typeNum = index[typeName]
      if id and typeNum then
        local row = Moves._rom and Moves._rom[id]
        if row then row.type = typeNum end
        local linked = Moves._linkRows and Moves._linkRows[id]
        if linked then linked.type = typeNum end
      end
    end
  end

  local function applyCategories(enable, Moves)
    if not FULL or not Moves then return end
    if not enable then
      for id, category in pairs(baseline.categories) do
        local row = Moves._rom and Moves._rom[id]
        if row then row.category = category end
        local linked = Moves._linkRows and Moves._linkRows[id]
        if linked then linked.category = category end
      end
      return
    end
    for name, category in pairs(data.move_categories or {}) do
      local id = moveId(Moves, name)
      if id then
        local row = Moves._rom and Moves._rom[id]
        if row then row.category = category end
        local linked = Moves._linkRows and Moves._linkRows[id]
        if linked then linked.category = category end
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

    if mode == "GEN9" then
      Types.useOverlay({
        table = flatChart(),
        physical = data.types.physical or {},
        names = data.types.names or {},
      })
      applySpeciesTypes(true, Pokemon)
      applyLearnsets(true, Pokemon)
      applyMoveTypes(true, Moves)
      applyCategories(true, Moves)
    else
      Types.clearOverlay()
      applySpeciesTypes(false, Pokemon)
      applyLearnsets(false, Pokemon)
      applyMoveTypes(false, Moves)
      applyCategories(false, Moves)
    end

    current = mode
    pcall(function() mod.save:set("mode", mode) end)
    invalidate()
    return true
  end

  local function toggleMode()
    local target = current == "GEN9" and "VANILLA" or "GEN9"
    local ok, why = apply(target)
    if not ok then
      if why == "battle" then
        mod.log:warn("BATTLE DATA cannot change during battle")
      elseif why == "data incomplete" then
        mod.log:warn("Gen 9 data is incomplete; run tools/export_showdown.py first")
      else
        mod.log:warn("BATTLE DATA switch failed: %s", tostring(why))
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
      step = function() return toggleMode() end,
    }

    local function toggleRow(id, label, key)
      out[#out + 1] = {
        id = id,
        label = label,
        value = function() return flag(key) and "ON" or "OFF" end,
        step = function() return toggleFlag(key) end,
      }
    end

    toggleRow("gen9_exp_catch", "EXP FOR CATCHING", "exp_catch")
    toggleRow("gen9_exp_share", "PARTY EXP SHARE", "exp_share")
    toggleRow("gen9_field_hms", "HMs WITHOUT MOVE", "field_hms")
    toggleRow("gen9_infinite_tms", "INFINITE TMS", "infinite_tms")
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

  -- Apply the saved mode once the engine has a save and a dataset.
  local function restore()
    if current ~= "GEN9" then return end
    local ok, why = apply("GEN9", true)
    if not ok then
      mod.log:warn("could not apply Gen 9 data: %s", tostring(why))
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
