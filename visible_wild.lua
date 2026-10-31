-- Visible wild encounters: the map's own wild Pokemon walk its encounter
-- tiles as overworld sprites instead of every step being a dice roll.
--
-- Behaviour, pacing and the encounter sequence follow pokeemerald-expansion
-- (src/wild_encounter_ow.c, data/scripts/wild_encounter.inc):
--
--   * MOVEMENT_SPEED_NORMAL is 16 frames a tile and sMovementDelaysOWE is
--     {64, 80, 96, 128}, so a step takes 0.27 s and a mon then stands for
--     1.07-2.13 s.  Times, not frame counts: the field tick is not
--     guaranteed to run once a frame.
--   * A mon notices the player in a cone 4 tiles deep and 3 wide, gives up
--     beyond 5 tiles, and every species defaults to OWE_IGNORE_PLAYER (the
--     whole shipped expansion has no species overriding it).
--   * Bumping into one plays the encounter script: the mon turns to face the
--     player, an exclamation mark pops, its cry plays, it walks up to the
--     player and only then does the battle start.

local VisibleWild = {}

local MAX = 6
local COUNTS = { 0, 2, 4, 6 }        -- OFF / FEW / SOME / MANY
local RANGE_X, RANGE_Y = 11, 6       -- spawn window, in tiles
local NEAREST = 3                    -- never closer than this
local FORGET = 15                    -- gone beyond this many tiles
local SPAWN_SECONDS = 2

-- pokeemerald-expansion's SpeedOWE, as seconds to cross one tile
local SPEED_SECONDS = {
  normal = 16 / 60, slow = 24 / 60, fast = 8 / 60, faster = 4 / 60,
}
-- sMovementDelaysOWE = {64, 80, 96, 128} frames
local IDLE_MIN, IDLE_MAX = 64 / 60, 128 / 60

-- InteractWithOverworldWildEncounter: emote, cry, then the approach
local NOTICE_SECONDS = 0.55
local APPROACH_PAUSE = 0.2
local APPROACH_ENABLED = true
local FLEE_GIVE_UP = 8               -- blocked steps before a cornered flee despawns

-- --- Behaviour table ------------------------------------------------------
-- gOWESpeciesBehavior in src/data/pokemon/wild_encounter_ow_behavior.h.
-- Every species defaults to IGNORE_PLAYER; data/owe_behavior.lua may map a
-- species id to any of these keys.
local BEHAVIOURS = {
  ignore = { move = "wander", view = 4, width = 3, active = 5,
             idle = "normal", activeSpeed = "normal", ret = "range" },
  chase = { move = "chase", view = 4, width = 3, active = 5,
            idle = "slow", activeSpeed = "slow", ret = "range" },
  flee = { move = "flee", view = 4, width = 3, active = 5,
           idle = "normal", activeSpeed = "normal", ret = "range" },
  watch = { move = "watch", view = 4, width = 3, active = 5,
            idle = "normal", activeSpeed = "normal", ret = "range" },
  approach = { move = "approach", view = 4, width = 3, active = 5,
               idle = "normal", activeSpeed = "slow", ret = "range" },
  despawn = { move = "despawn", view = 4, width = 3, active = 5,
              idle = "normal", activeSpeed = "normal", ret = "range" },
}

local DIRS = {
  up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 },
}
local FACING = {
  [0] = "down", [1] = "up", [2] = "left", [3] = "right",
}

function VisibleWild.count(index)
  return COUNTS[tonumber(index) or 1] or 0
end

local entries = {}
local currentMap
local spawnAt = 0
local uid = 0
local owner = nil
local busyEntry = nil          -- the one playing the encounter sequence
local steppingMon = false      -- our own Collision.canEnter call is in flight

local function rt(name)
  local m = package.loaded[name]
  if type(m) == "table" then return m end
  local ok, v = pcall(require, name)
  return ok and v or nil
end

local function session()
  local R = rt("src.core.game3.runtime")
  return R and R.getSession and R.getSession()
end

local function currentGame()
  local R = rt("src.core.game3.runtime")
  return R and R._game
end

local function playerOf()
  return rt("src.core.game3.player")
end

local function now()
  return love and love.timer and love.timer.getTime and love.timer.getTime() or os.clock()
end

local function speciesIdOf(value)
  local id = tonumber(value)
  if id then return id end
  if type(value) == "string" then
    local P = rt("src.core.game3.pokemon")
    return P and P.speciesFromName and P.speciesFromName(value) or nil
  end
  return nil
end

--- One slot of the map's land table, weighed like the game weighs it.
local function pickSlot(mapId)
  local E = rt("src.core.game3.encounters")
  local t = E and E.tableFor and E.tableFor(mapId)
  if type(t) ~= "table" then return nil end
  local area = t.land or t.grass
  local slots = type(area) == "table" and (area.slots or area.mons or area) or nil
  if type(slots) ~= "table" or #slots == 0 then return nil end
  local total = 0
  for _, e in ipairs(slots) do
    if type(e) == "table" then
      total = total + (tonumber(e.weight) or tonumber(e.chance) or 1)
    end
  end
  if total <= 0 then return nil end
  local roll = math.random(total)
  local acc = 0
  for _, e in ipairs(slots) do
    if type(e) == "table" then
      acc = acc + (tonumber(e.weight) or tonumber(e.chance) or 1)
      if roll <= acc then
        local id = speciesIdOf(e.species or e[1])
        if id then
          local lo = tonumber(e.minLevel or e.level or e[2]) or 2
          local hi = tonumber(e.maxLevel or e.level or e[2]) or lo
          if hi < lo then hi = lo end
          return { species = id, level = lo + math.random(hi - lo + 1) - 1 }
        end
      end
    end
  end
  return nil
end

local function occupied(x, y)
  for _, e in ipairs(entries) do
    if e.cellX == x and e.cellY == y then return true end
  end
  return false
end

local function passable(game, x, y, fromX, fromY)
  local C = rt("src.core.game3.collision")
  if C and C.canEnter then
    local dx = x - (fromX or x)
    local dy = y - (fromY or y)
    local dir = (dx > 0 and "right") or (dx < 0 and "left")
      or (dy > 0 and "down") or "up"
    -- The mod wraps Collision.canEnter to start battles; a mon taking a step
    -- must not be mistaken for the player walking into one.
    steppingMon = true
    local ok = C.canEnter(game, x, y, {
      fromX = fromX or x, fromY = fromY or y, dir = dir,
      elevation = 3,
    })
    steppingMon = false
    if ok == false then return false end
  end
  return true
end

--- True while a mon is testing the next tile.  The battle trigger ignores
--- these calls.
function VisibleWild.isStepping()
  return steppingMon
end

-- Spawning and wandering both stay on tiles the map lists as wild ground, so
-- an icon never stands on a path or a rooftop.
local function wildGround(x, y)
  local E = rt("src.core.game3.encounters")
  if not (E and E.terrainAt) then return true end
  local ok, terrain = pcall(E.terrainAt, x, y)
  if not ok or terrain == nil then
    -- Caves and a few indoor maps have no encounter-type table, so terrainAt
    -- comes back nil on every tile.  Treat that as "anywhere walkable" rather
    -- than spawning nothing at all.
    return true
  end
  return terrain == "land"
end

-- Overworld sheets shipped with the mod: 192x32, six 32x32 frames
-- (down 0-1, up 2-3, side 4-5).  Loaded through the mod sandbox, never from
-- an absolute path.
local function owImage(species)
  if not owner or not owner.mod then return nil end
  local cache = owner.owCache
  if not cache then cache = {}; owner.owCache = cache end
  local id = tonumber(species)
  if not id then return nil end
  -- Encounter slots carry the game's internal species id.  The sheets are
  -- filed by national dex number (Rahtak's folders are named that way), so a
  -- raw id picks the wrong Pokemon: internal 318 is Baltoy, national 318 is
  -- Carvanha.
  local Pm = rt("src.core.game3.pokemon")
  if Pm and Pm.national then id = Pm.national(id) or id end
  local hit = cache[id]
  if hit ~= nil then return hit or nil end
  if owner.owList and not owner.owList[id] then cache[id] = false; return nil end
  local ok, bytes = pcall(function() return owner.mod:read("assets/pokemon_ow/" .. id .. ".png") end)
  if not ok or type(bytes) ~= "string" or #bytes == 0 then
    cache[id] = false
    return nil
  end
  local made = pcall(function()
    local fd = love.filesystem.newFileData(bytes, tostring(id) .. ".png")
    local data = love.image.newImageData(fd)
    local img = love.graphics.newImage(data)
    if img.setFilter then img:setFilter("nearest", "nearest") end
    cache[id] = img
  end)
  if not made then cache[id] = false end
  return cache[id] or nil
end

local function owQuad(img, frame)
  local key = "ow:" .. tostring(img) .. ":" .. tostring(frame)
  local store = owner.owQuads
  if not store then store = {}; owner.owQuads = store end
  local q = store[key]
  if not q then
    q = love.graphics.newQuad(frame * 32, 0, 32, 32, 192, 32)
    store[key] = q
  end
  return q
end

local function painter(entry)
  return function(self, camX, camY)
    local SX = (self.x or 0) - (camX or 0) - 8
    local SY = (self.y or 0) - (camY or 0) - 16
    love.graphics.setBlendMode("alpha")

    local facing = entry.facing or "down"
    local walking = (entry.stepAnim or 0) > 0
    local frame
    if facing == "up" then frame = walking and 3 or 2
    elseif facing == "left" or facing == "right" then frame = walking and 5 or 4
    else frame = walking and 1 or 0 end

    local img = owImage(entry.species)
    if img then
      local flip = facing == "right" and -1 or 1
      local ox = flip < 0 and 32 or 0
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(img, owQuad(img, frame), SX + ox, SY, 0, flip, 1)
    else
      -- No sheet for this species: fall back to the 32x32 party icon.
      local P = rt("src.core.game3.pokemon")
      local icon = P and P.icon and P.icon(entry.species)
      if icon and icon.image then
        local q = icon.quads and (icon.quads[0] or icon.quads[1])
        love.graphics.setColor(1, 1, 1, 1)
        if q then love.graphics.draw(icon.image, q, SX, SY)
        else love.graphics.draw(icon.image, SX, SY) end
      end
    end

    if entry.shiny then
      local t = now()
      for i = 1, 4 do
        local a = t * 2.2 + i * math.pi / 2
        local r = 17 + math.sin(t * 5 + i) * 3
        local px = SX + 16 + math.cos(a) * r
        local py = SY + 16 + math.sin(a) * r * 0.55
        local size = 1.4 + math.sin(t * 9 + i * 2) * 0.7
        love.graphics.setColor(1, 0.96, 0.72, 0.95)
        love.graphics.circle("fill", px, py, size)
      end
      love.graphics.setColor(1, 1, 1, 1)
    end
  end
end

local function attach(entry)
  local Objects = rt("src.core.game3.objects")
  if not (Objects and Objects.find) then return false end
  local eo = Objects.find(entry.localId)
  if not eo then return false end
  eo.draw = painter(entry)
  if entry.def then entry.def.draw = eo.draw end
  -- Some spawn paths leave runtime events visible=false; the draw list skips
  -- those, so turn the flag on unconditionally.
  eo.visible, eo.hidden = true, false
  entry.eo = eo
  entry.attached = true
  return true
end

-- --- movement -------------------------------------------------------------

local function setFacing(entry, facing)
  if not facing or entry.facing == facing then return end
  entry.facing = facing
  if entry.eo then entry.eo.facing = facing end
  if entry.def then entry.def.facing = facing end
end

local function faceTowards(entry, px, py)
  local dx, dy = px - entry.cellX, py - entry.cellY
  local horizontal = math.abs(dx) >= math.abs(dy)
  if horizontal and dx ~= 0 then setFacing(entry, dx > 0 and "right" or "left")
  elseif dy ~= 0 then setFacing(entry, dy > 0 and "down" or "up") end
end

local function canStand(game, entry, tx, ty, px, py)
  if tx == px and ty == py then return false end
  if occupied(tx, ty) then return false end
  if not wildGround(tx, ty) then return false end
  return passable(game, tx, ty, entry.cellX, entry.cellY)
end

local function startStep(entry, dx, dy, speed)
  local tx, ty = entry.cellX + dx, entry.cellY + dy
  local fromX = entry.px or (entry.cellX * 16)
  local fromY = entry.py or (entry.cellY * 16)
  entry.cellX, entry.cellY = tx, ty
  setFacing(entry, (dx > 0 and "right") or (dx < 0 and "left")
    or (dy > 0 and "down") or "up")
  entry.stepAnim = 8
  entry.fromX, entry.fromY = fromX, fromY
  entry.targetPx, entry.targetPy = tx * 16, ty * 16
  entry.moveStart = now()
  entry.moveSeconds = SPEED_SECONDS[speed] or SPEED_SECONDS.normal
  entry.moving = true
  if entry.def then entry.def.x, entry.def.y = tx, ty end
  if entry.eo then
    entry.eo.x, entry.eo.y = tx * 16, ty * 16
    entry.eo.cellX, entry.eo.cellY = tx, ty
    entry.eo.facing = entry.facing
  end
end

local function tryStep(game, entry, dx, dy, speed, px, py)
  local tx, ty = entry.cellX + dx, entry.cellY + dy
  if not canStand(game, entry, tx, ty, px, py) then return false end
  startStep(entry, dx, dy, speed)
  return true
end

--- MOVEMENT_TYPE_WANDER_AROUND_OWE: three times in four it turns 90 degrees,
--- the rest of the time it keeps going.  It never turns around.
local function turn90(facing, side)
  if facing == "up" then return side == 1 and "left" or "right" end
  if facing == "down" then return side == 1 and "right" or "left" end
  if facing == "left" then return side == 1 and "down" or "up" end
  return side == 1 and "up" or "down"
end

local function wanderStep(game, entry, px, py)
  local speed = entry.behaviour.idle
  local facing = entry.facing or "down"
  local tries = {}
  if math.random(4) == 1 then tries[#tries + 1] = facing
  else tries[#tries + 1] = turn90(facing, math.random(2) == 1) end
  tries[#tries + 1] = turn90(facing, 1)
  tries[#tries + 1] = turn90(facing, 2)
  for _, dir in ipairs(tries) do
    local d = DIRS[dir]
    if tryStep(game, entry, d[1], d[2], speed, px, py) then return true end
  end
  return false
end

--- Chase / flee / approach all reduce or grow the distance one tile at a
--- time, preferring the longer axis and falling back to the other one.
local function stepTowards(game, entry, px, py, speed, away)
  local dx, dy = px - entry.cellX, py - entry.cellY
  if away then dx, dy = -dx, -dy end
  local firstX = math.abs(dx) >= math.abs(dy)
  local order = {}
  if firstX then
    if dx ~= 0 then order[#order + 1] = { dx = dx > 0 and 1 or -1, dy = 0 } end
    if dy ~= 0 then order[#order + 1] = { dx = 0, dy = dy > 0 and 1 or -1 } end
  else
    if dy ~= 0 then order[#order + 1] = { dx = 0, dy = dy > 0 and 1 or -1 } end
    if dx ~= 0 then order[#order + 1] = { dx = dx > 0 and 1 or -1, dy = 0 } end
  end
  for _, d in ipairs(order) do
    if tryStep(game, entry, d.dx, d.dy, speed, px, py) then return true end
  end
  return false
end

-- --- notice / behaviour ---------------------------------------------------

local function playerRunning(P)
  return P and (P.running or P.biking or P.moving) and true or false
end

--- CanAwareOWESeePlayer: cone in front of the mon, plus "the player dashed
--- past close by" which notices regardless of facing.
local function seesPlayer(entry, px, py, P)
  local b = entry.behaviour
  if b.move == "wander" then return false end
  local distX, distY = math.abs(px - entry.cellX), math.abs(py - entry.cellY)
  if playerRunning(P) and (distX + distY) <= b.active then return true end
  local half = math.floor((b.width - 1) / 2)
  local f = entry.facing or "down"
  if f == "up" then
    return py <= entry.cellY and entry.cellY - py <= b.view and distX <= half
  elseif f == "down" then
    return py >= entry.cellY and py - entry.cellY <= b.view and distX <= half
  elseif f == "left" then
    return px <= entry.cellX and entry.cellX - px <= b.view and distY <= half
  end
  return px >= entry.cellX and px - entry.cellX <= b.view and distY <= half
end

local function distToPlayer(entry, px, py)
  return math.abs(entry.cellX - px) + math.abs(entry.cellY - py)
end

local function playEmote(entry)
  local FE = rt("src.core.game3.field_effects")
  if FE and FE.startEmote and entry.eo then
    pcall(FE.startEmote, entry.eo, "exclamation")
  end
end

local function playCry(entry)
  local A = rt("src.core.game3.audio")
  if A and A.playCry then pcall(A.playCry, entry.species, 0) end
end

local function setFieldLocked(entry, locked)
  local F = rt("src.core.game3.field")
  if not F then return end
  if locked then
    entry.wasLocked = F.locked and true or false
    F.locked = true
  else
    F.locked = entry.wasLocked and true or false
    entry.wasLocked = nil
  end
end

local function finishEncounter(entry, failed)
  setFieldLocked(entry, false)
  entry.phase = nil
  if busyEntry == entry then busyEntry = nil end
  if failed then
    -- The battle never started: keep the mon rather than deleting it.
    entry.nextMoveAt = now() + 2
  end
end

--- Advance the encounter sequence.  Returns true when the entry is gone.
local removeEntry  -- defined below; advanceEncounter removes entries too

local function advanceEncounter(entry, game, px, py)
  local phase = entry.phase
  if phase == "notice" then
    if now() - (entry.phaseAt or 0) < NOTICE_SECONDS then return false end
    local gap = distToPlayer(entry, px, py)
    if APPROACH_ENABLED and gap > 1 then
      entry.phase, entry.phaseAt = "approach", now()
      entry.nextMoveAt = now()
    else
      entry.phase, entry.phaseAt = "battle", now()
    end
    return false
  end

  if phase == "approach" then
    if entry.moving then return false end
    local gap = distToPlayer(entry, px, py)
    if gap <= 1 then
      faceTowards(entry, px, py)
      entry.phase, entry.phaseAt = "battle", now()
      return false
    end
    if now() < (entry.nextMoveAt or 0) then return false end
    local moved = stepTowards(game, entry, px, py, "slow", false)
    if not moved then faceTowards(entry, px, py) end
    entry.nextMoveAt = now() + 0.12
    return false
  end

  if phase == "vanish" then
    if now() - (entry.phaseAt or 0) < 0.5 then return false end
    if owner.log then
      owner.log:info("VWLOG vanish %s lv%d at %d,%d", tostring(entry.species),
        entry.level, entry.cellX, entry.cellY)
    end
    removeEntry(entry)
    finishEncounter(entry, false)
    return true
  end

  -- battle
  if entry.moving then return false end
  if now() - (entry.phaseAt or 0) < APPROACH_PAUSE then return false end
  entry.phase = nil
  setFieldLocked(entry, false)
  local ok, err = true, nil
  if owner.startBattle then
    local called
    called, ok, err = pcall(owner.startBattle, entry)
    if not called then ok, err = false, "threw: " .. tostring(ok) end
  end
  if ok then
    if owner.log then
      owner.log:info("VWLOG battle %s dex %s lv%d at %d,%d", tostring(entry.species),
        tostring(entry.dex), entry.level, entry.cellX, entry.cellY)
    end
    removeEntry(entry)
    if busyEntry == entry then busyEntry = nil end
    -- The spec's two-second refill: a battled mon is gone, and the map does
    -- not refill on the same frame.
    spawnAt = now() + SPAWN_SECONDS
    return true
  end
  if owner.log then
    owner.log:info("VWLOG battle failed %s: %s", tostring(entry.species), tostring(err))
  end
  finishEncounter(entry, true)
  return false
end

--- Idle/active behaviour for one mon that is not in an encounter sequence.
local function stepBehaviour(entry, game, px, py, P)
  local b = entry.behaviour
  if b.move ~= "wander" then
    if entry.active then
      local far = distToPlayer(entry, px, py)
      if (b.ret == "range" and far > b.active) then
        entry.active = false
      end
    elseif seesPlayer(entry, px, py, P) then
      entry.active = true
      entry.fleeBlocked = 0
      if b.move == "despawn" then
        playEmote(entry)
        entry.phase, entry.phaseAt = "vanish", now()
        busyEntry = entry
        return
      end
    end
  end

  if not entry.active then
    if entry.moving or now() < (entry.nextMoveAt or 0) then return end
    if not wanderStep(game, entry, px, py) then
      entry.nextMoveAt = now() + 0.3
      return
    end
    entry.nextMoveAt = now() + IDLE_MIN + math.random() * (IDLE_MAX - IDLE_MIN)
    return
  end

  if entry.moving then return end
  if b.move == "watch" then
    faceTowards(entry, px, py)
    entry.nextMoveAt = now() + 0.25
    return
  end
  if now() < (entry.nextMoveAt or 0) then return end
  if b.move == "chase" then
    -- Walking into the player is the collision that starts the battle, the
    -- same way a chasing OWE triggers in expansion.
    if distToPlayer(entry, px, py) <= 1 then
      VisibleWild.beginEncounter(entry)
      return
    end
    if stepTowards(game, entry, px, py, b.activeSpeed, false) then
      entry.nextMoveAt = now() + 0.05
    else
      entry.nextMoveAt = now() + 0.3
    end
    return
  end
  if b.move == "flee" then
    if stepTowards(game, entry, px, py, b.activeSpeed, true) then
      entry.fleeBlocked = 0
    else
      entry.fleeBlocked = (entry.fleeBlocked or 0) + 1
      if entry.fleeBlocked >= FLEE_GIVE_UP then
        -- WE_OWE_FLEE_DESPAWN: a cornered flee gives up and disappears.
        if owner.log then
          owner.log:info("VWLOG cornered %s lv%d at %d,%d", tostring(entry.species),
            entry.level, entry.cellX, entry.cellY)
        end
        removeEntry(entry)
        entry.removeNow = true
        return
      end
    end
    entry.nextMoveAt = now() + 0.08
    return
  end
  -- approach: keep one tile of distance, face the player otherwise
  if distToPlayer(entry, px, py) <= 1 then
    faceTowards(entry, px, py)
    entry.nextMoveAt = now() + 0.3
  elseif stepTowards(game, entry, px, py, b.activeSpeed, false) then
    entry.nextMoveAt = now() + 0.08
  else
    faceTowards(entry, px, py)
    entry.nextMoveAt = now() + 0.3
  end
end

local function spawnOne(game, mapId)
  -- Spawning before the map loader has adopted the map puts the event in the
  -- foreign pool: Objects.find cannot see it, the painter never attaches and
  -- it renders as graphics id 0 (the player).  Wait one frame instead.
  local Objects = rt("src.core.game3.objects")
  if Objects and Objects._mapId ~= nil and Objects._mapId ~= mapId then
    return false
  end
  local pick = pickSlot(mapId)
  if not pick then return false end
  local P = playerOf()
  if not (P and P.cellX) then return false end
  local px, py = P.cellX, P.cellY
  for _ = 1, 40 do
    local dx = math.random(-RANGE_X, RANGE_X)
    local dy = math.random(-RANGE_Y, RANGE_Y)
    if math.abs(dx) >= NEAREST or math.abs(dy) >= NEAREST then
      local x, y = px + dx, py + dy
      if not occupied(x, y) and wildGround(x, y) and passable(game, x, y, px, py) then
        local id = owner.world:spawnNpc(mapId, {
          x = x, y = y, elevation = 3, facing = "down",
          movementType = 0, graphicsId = 0,
          wildIcon = true,
        })
        if id then
          local Objects = rt("src.core.game3.objects")
          local defs = Objects and Objects.runtimeByMap and Objects.runtimeByMap[mapId]
          local added = defs and defs[#defs]
          uid = uid + 1
          local Pm = rt("src.core.game3.pokemon")
          local Rng = rt("src.core.game3.rng")
          local pid = (Rng and Rng.Random32 and Rng.Random32()) or math.random(0, 0xFFFFFFFF)
          local gender = "U"
          if Pm and Pm.gender then
            local okG, g = pcall(Pm.gender, pick.species, pid)
            if okG and g then gender = g end
          end
          local behaviour = "ignore"
          if owner.behaviourFor then
            local okB, b = pcall(owner.behaviourFor, pick.species)
            if okB and type(b) == "string" and BEHAVIOURS[b] then behaviour = b end
          end
          local entry = {
            uid = uid, npcId = id, species = pick.species, level = pick.level,
            cellX = x, cellY = y, facing = "down",
            px = x * 16, py = y * 16,
            nextMoveAt = now() + IDLE_MIN + math.random() * (IDLE_MAX - IDLE_MIN),
            localId = added and added.localId or nil,
            def = added,
            behaviour = BEHAVIOURS[behaviour],
            behaviourName = behaviour,
            pid = pid,
            gender = gender,
            shiny = owner.isShiny and owner.isShiny() or false,
          }
          entry.dex = Pm and Pm.national and Pm.national(pick.species) or nil
          entries[#entries + 1] = entry
          if not attach(entry) then
            -- Without a painter the event falls back to graphics id 0, which
            -- is the player character in FireRed.  Drop it rather than let a
            -- Brendan clone wander the map.
            removeEntry(entry, true)
            table.remove(entries)
            return false
          end
          if entry.shiny then
            local okA, Audio = pcall(require, "src.core.game3.audio")
            local okS, SE = pcall(require, "src.core.game3.se_ids")
            if okA and Audio and Audio.playSe and okS and SE and SE.SE_SHINY then
              pcall(Audio.playSe, SE.SE_SHINY)
            end
          end
          if owner.log then
            owner.log:info("visible wild: internal %s (dex %s) lv%d at %d,%d (npc %s, %s)",
              tostring(pick.species), tostring(entry.dex), pick.level, x, y,
              tostring(added and added.localId), behaviour)
          end
          return true
        end
      end
    end
  end
  return false
end

function removeEntry(entry, force)
  if not (entry and entry.npcId) then return end
  local Objects = rt("src.core.game3.objects")
  local removed = false
  -- The world API refuses while something else owns the field (starting a
  -- battle is one of those moments), so fall through to the object pool and
  -- take the event out directly.  It is our own runtime object either way.
  if owner.world and owner.world.removeNpc then
    local okR, r1, r2 = pcall(owner.world.removeNpc, owner.world, entry.npcId)
    removed = okR and r1 ~= nil
    if not removed and owner.log then
      owner.log:info("VWLOG removeNpc %s refused (%s), removing directly",
        tostring(entry.npcId), tostring(r2 or r1))
    end
  end
  if not removed and Objects and Objects.removeRuntimeObject then
    pcall(Objects.removeRuntimeObject, entry.npcId)
  end
end

function VisibleWild.clear()
  -- A map change in the middle of an encounter must not leave the field
  -- locked: the player would never move again.
  if busyEntry then setFieldLocked(busyEntry, false) end
  for _, e in ipairs(entries) do removeEntry(e) end
  entries = {}
  busyEntry = nil
  spawnAt = now()
end

function VisibleWild.most()
  return VisibleWild.count(owner.setting and owner.setting() or 1)
end

--- Live entries, for other systems that want their positions.
function VisibleWild.all()
  return entries
end

function VisibleWild.at(x, y)
  for _, e in ipairs(entries) do
    if e.cellX == x and e.cellY == y then return e end
  end
end

--- Remove runtime events this mod owns that lost their painter.  A stray one
--- renders as graphics id 0, which is the player sprite, and cannot be
--- interacted with - exactly what shows up after walking in and out of a cave
--- a few times.
function VisibleWild.sweep()
  local Objects = rt("src.core.game3.objects")
  if not (Objects and Objects.forDraw and Objects.removeRuntimeObject) then return end
  for _, eo in ipairs(Objects.forDraw()) do
    local def = eo.def
    if def and def.wildIcon and not eo.draw then
      pcall(Objects.removeRuntimeObject, eo.id)
    end
  end
end

--- Start the encounter script: face the player, "!", cry, then walk over.
--- Returns true when the step must be blocked (always, while it runs).
function VisibleWild.beginEncounter(entry)
  if not entry then return false end
  if entry.phase then return true end
  if busyEntry and busyEntry ~= entry then return true end
  local P = playerOf()
  if P and P.cellX then faceTowards(entry, P.cellX, P.cellY) end
  busyEntry = entry
  entry.phase, entry.phaseAt = "notice", now()
  entry.active = false
  setFieldLocked(entry, true)
  playEmote(entry)
  playCry(entry)
  if owner.log then
    owner.log:info("VWLOG notice %s lv%d at %d,%d (player %s,%s) facing %s",
      tostring(entry.species), entry.level, entry.cellX, entry.cellY,
      tostring(P and P.cellX), tostring(P and P.cellY), tostring(entry.facing))
  end
  return true
end

function VisibleWild.isBusy()
  return busyEntry ~= nil
end

--- Called once per player step and once per frame.
function VisibleWild.update()
  local s = session()
  local mapId = s and s.map
  if mapId ~= currentMap then
    currentMap = mapId
    VisibleWild.clear()
    if owner.log and mapId then
      owner.log:info("visible wild: map %s", tostring(mapId))
    end
  end
  local most = VisibleWild.most()
  if most <= 0 or not mapId then
    if #entries > 0 then VisibleWild.clear() end
    return
  end
  local P = playerOf()
  if not (P and P.cellX) then return end
  local game = currentGame()
  local px, py = P.cellX, P.cellY

  for i = #entries, 1, -1 do
    local e = entries[i]
    if e.stepAnim and e.stepAnim > 0 then e.stepAnim = e.stepAnim - 1 end
    if e.moving then
      local t = math.min(1, (now() - (e.moveStart or 0)) / (e.moveSeconds or SPEED_SECONDS.normal))
      e.px = e.fromX + (e.targetPx - e.fromX) * t
      e.py = e.fromY + (e.targetPy - e.fromY) * t
      -- Only the pixel position, never eo.moving: that flag belongs to the
      -- engine's own object movement, and setting it makes tickMotion snap
      -- the actor back to its previous cell when its step finishes.
      if e.eo then e.eo.px, e.eo.py = e.px, e.py end
      if t >= 1 then
        e.moving = false
        e.px, e.py = e.targetPx, e.targetPy
        if e.eo then e.eo.px, e.eo.py = e.px, e.py end
        if not e.active and not e.phase then
          e.nextMoveAt = now() + IDLE_MIN + math.random() * (IDLE_MAX - IDLE_MIN)
        end
      end
    end
    if not e.attached or not (e.eo and e.eo.draw) then
      e.attached = nil
      if attach(e) then
        e.retry = nil
      elseif e.retry then
        -- Two frames without a handle: the event is stray, drop it.
        removeEntry(e, true)
        table.remove(entries, i)
      else
        e.retry = true
      end
    end
    if e.phase or busyEntry == e then
      if advanceEncounter(e, game, px, py) then table.remove(entries, i) end
    elseif math.abs(e.cellX - px) > FORGET or math.abs(e.cellY - py) > FORGET then
      if owner.log then
        owner.log:info("VWLOG forget %s lv%d at %d,%d (player %d,%d)",
          tostring(e.species), e.level, e.cellX, e.cellY, px, py)
      end
      removeEntry(e)
      table.remove(entries, i)
    else
      stepBehaviour(e, game, px, py, P)
      if e.removeNow then table.remove(entries, i) end
    end
  end

  -- The sequence entry can be swept or dropped elsewhere; never leave the
  -- field locked behind it.
  if busyEntry then
    local alive = false
    for _, e in ipairs(entries) do
      if e == busyEntry then alive = true break end
    end
    if not alive then finishEncounter(busyEntry, false) end
  end

  VisibleWild.sweep()

  if #entries < most and now() >= spawnAt then
    -- Walking into a map should show Pokemon straight away: fill the whole
    -- allowance on the first pass, then top up one every two seconds.
    local want = (#entries == 0) and most or 1
    local spawned = false
    for _ = 1, want do
      if #entries >= most then break end
      if not spawnOne(game, mapId) then break end
      spawned = true
    end
    -- Only start the two-second clock once something actually appeared; a
    -- failed attempt (map still loading) retries on the next update.
    if spawned then spawnAt = now() + SPAWN_SECONDS end
  end
end

function VisibleWild.remove(entry)
  if not entry then return end
  for i, e in ipairs(entries) do
    if e == entry then
      removeEntry(e)
      table.remove(entries, i)
      if busyEntry == e then busyEntry = nil end
      return
    end
  end
end

function VisibleWild.setup(mod, opts)
  owner = {
    modId = mod.id,
    mod = mod,
    owList = opts.owList,
    world = mod.world,
    setting = opts.setting,
    isShiny = opts.isShiny,
    behaviourFor = opts.behaviourFor,
    startBattle = opts.startBattle,
    objects = nil,
    log = opts.log,
  }
  return VisibleWild
end

return VisibleWild
