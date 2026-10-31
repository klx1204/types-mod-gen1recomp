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
-- pokeemerald-expansion OWE_SPAWN_WIDTH_TOTAL 15 / HEIGHT_TOTAL 9: the whole
-- GBA view.  The near limit stays at 3 so nothing pops in under the player.
local RANGE_X, RANGE_Y = 7, 4        -- spawn window radius, in tiles
local NEAREST = 3                    -- never closer than this
local FORGET = 15                    -- gone beyond this many tiles
-- SetNewOWESpawnCountdown: 30 frames plus 30 per mon already out.
local SPAWN_FRAMES_MIN, SPAWN_FRAMES_PER = 30, 30

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
-- Spawn/despawn: a short rise out of the ground and a sink back into it.
local APPEAR_SECONDS = 0.2
local VANISH_SECONDS = 0.2
-- OWE_SPAWN_DISTANCE_WATER: three tiles away while riding the water.
local WATER_NEAREST = 3
-- APPROACH_PLAYER_OWE's excited hop
local HOP_SECONDS = 0.3

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

local function refillDelay()
  return (SPAWN_FRAMES_MIN + SPAWN_FRAMES_PER * #entries) / 60
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
local function pickSlot(mapId, kind)
  local E = rt("src.core.game3.encounters")
  local t = E and E.tableFor and E.tableFor(mapId)
  if type(t) ~= "table" then return nil end
  local area
  if kind == "water" or kind == "underwater" then
    area = t.water
  else
    area = t.land or t.grass
  end
  local slots = type(area) == "table" and (area.slots or area.mons or area) or nil
  if type(slots) ~= "table" or #slots == 0 then return nil end
  -- pret's land slot percentages: 20,20,10,10,10,10,5,5,4,4,1,1.  Without
  -- them every slot is equally likely and the 1% species turn up as often as
  -- the common ones.
  local weights
  if kind == "water" or kind == "underwater" then
    weights = (E._h and E._h.WATER_WEIGHTS) or { 60, 30, 5, 4, 1 }
  else
    weights = E.LAND_WEIGHTS or { 20, 20, 10, 10, 10, 10, 5, 5, 4, 4, 1, 1 }
  end
  local function slotWeight(i, e)
    return tonumber(e.weight) or tonumber(e.chance) or weights[i] or 1
  end
  local total = 0
  for i, e in ipairs(slots) do
    if type(e) == "table" then total = total + slotWeight(i, e) end
  end
  if total <= 0 then return nil end
  -- pret Random() % total, then cumulative slots: same stream the engine's own
  -- ChooseWildMonIndex_Land uses.
  local Rng = rt("src.core.game3.rng")
  local function rand(n)
    if Rng and Rng.Random then return Rng.Random() % n end
    return math.random(n) - 1
  end
  local roll = rand(total)
  local acc = 0
  for i, e in ipairs(slots) do
    if type(e) == "table" then
      acc = acc + slotWeight(i, e)
      if roll < acc then
        local id = speciesIdOf(e.species or e[1])
        if id then
          -- ChooseWildMonLevel: lo + Random() % (hi - lo + 1)
          local lo = tonumber(e.minLevel or e.level or e[2]) or 2
          local hi = tonumber(e.maxLevel or e.level or e[2]) or lo
          if hi < lo then hi = lo end
          return { species = id, level = lo + rand(hi - lo + 1) }
        end
      end
    end
  end
  return nil
end

--- What the player is riding decides which table and which tiles are in play.
local function spawnKind()
  local P = playerOf()
  if P and P.underwater then return "underwater" end
  if P and P.surfing then return "water" end
  return "land"
end

local function occupied(x, y)
  for _, e in ipairs(entries) do
    if e.cellX == x and e.cellY == y then return true end
  end
  return false
end

local function passable(game, x, y, fromX, fromY, elevation)
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
      elevation = elevation or 3,
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
local function wildGround(x, y, kind)
  local C = rt("src.core.game3.collision")
  if kind == "underwater" then
    -- underwater maps have no water metatiles; the sea floor is ordinary
    -- walkable geometry
    return (C and C.isWalkable and C.isWalkable(x, y)) or false
  end
  if kind == "water" then
    return (C and C.isWater and C.isWater(x, y)) or false
  end
  if C and C.isWater and C.isWater(x, y) then return false end
  local E = rt("src.core.game3.encounters")
  if not (E and E.terrainAt) then return C and C.isGrass and C.isGrass(x, y) or false end
  local ok, terrain = pcall(E.terrainAt, x, y)
  if ok and terrain == "land" then return true end
  if ok and terrain == "water" then return false end
  -- terrainAt is nil when this metatile is not an encounter tile (a path, a
  -- floor tile) -- spawning there put wild Pokemon on roads.  Only a map that
  -- has no encounter table at all falls back to "any walkable, non-water tile".
  local s = session()
  local mapId = s and s.map
  local table_ = mapId and E.tableFor and E.tableFor(mapId) or nil
  if table_ then return false end
  return true
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

--- Shared with the follower: the same sheets, the same quads.
function VisibleWild.owImage(species) return owImage(species) end

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

function VisibleWild.owQuad(img, frame) return owQuad(img, frame) end

local function painter(entry)
  return function(self, camX, camY)
    local rise = 1
    if entry.appearAt then
      rise = math.min(1, (now() - entry.appearAt) / APPEAR_SECONDS)
    end
    local sink = 0
    if entry.vanishAt then
      sink = math.min(1, (now() - entry.vanishAt) / VANISH_SECONDS)
    end
    local yOff = (1 - rise) * 6 + sink * 6
    if entry.hopStart then
      local h = (now() - entry.hopStart) / HOP_SECONDS
      if h > 0 and h < 1 then yOff = yOff - math.sin(h * math.pi) * 6 end
    end
    local alpha = rise * (1 - sink)
    local SX = (self.x or 0) - (camX or 0) - 8
    local SY = (self.y or 0) - (camY or 0) - 16 + yOff
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
      love.graphics.setColor(1, 1, 1, alpha)
      love.graphics.draw(img, owQuad(img, frame), SX + ox, SY, 0, flip, 1)
    else
      -- No sheet for this species: fall back to the 32x32 party icon.
      local P = rt("src.core.game3.pokemon")
      local icon = P and P.icon and P.icon(entry.species)
      if icon and icon.image then
        local q = icon.quads and (icon.quads[0] or icon.quads[1])
        love.graphics.setColor(1, 1, 1, alpha)
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
        love.graphics.setColor(1, 0.96, 0.72, 0.95 * alpha)
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
  -- WE_OWE_RESTRICT_MAP: never step off the current map.
  local C0 = rt("src.core.game3.collision")
  if C0 and C0.inBounds and not C0.inBounds(tx, ty) then return false end
  if occupied(tx, ty) then return false end
  if not wildGround(tx, ty, entry.kind) then return false end
  -- WE_OWE_RESTRICT_METATILE: a mon stays on the kind of tile it spawned on,
  -- so a tall-grass encounter never wanders out onto the path or the water.
  if entry.terrain ~= nil then
    local C = rt("src.core.game3.collision")
    if C and C.behavior and C.behavior(tx, ty) ~= entry.terrain then return false end
  end
  return passable(game, tx, ty, entry.cellX, entry.cellY, entry.elevation)
end

local function startStep(entry, dx, dy, speed)
  local tx, ty = entry.cellX + dx, entry.cellY + dy
  local fromX = entry.px or (entry.cellX * 16)
  local fromY = entry.py or (entry.cellY * 16)
  -- pokeemerald checks currentCoords and previousCoords when it looks for a
  -- collision, so the cell a mon is stepping off still counts while it moves.
  entry.prevX, entry.prevY = entry.cellX, entry.cellY
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

--- The cells the player occupies: where it stands, and where it is stepping.
local function playerCells(P)
  local cells = {}
  if not (P and P.cellX and P.cellY) then return cells end
  cells[1] = { P.cellX, P.cellY }
  if P.moving and P.targetX and P.targetY then
    cells[2] = { P.targetX, P.targetY }
  end
  return cells
end

local function touchesPlayer(cells, x, y)
  for _, c in ipairs(cells) do
    if c[1] == x and c[2] == y then return true end
  end
  return false
end

local function tryStep(game, entry, dx, dy, speed, px, py)
  local tx, ty = entry.cellX + dx, entry.cellY + dy
  -- Walking into the player is the collision that starts the battle, no
  -- matter which side moved first (expansion triggers from both).
  if touchesPlayer(playerCells(playerOf()), tx, ty) then
    VisibleWild.beginEncounter(entry)
    return false
  end
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

--- Breadth-first search for the first step of a path that goes around
--- whatever blocks the direct line.  Goals are the cells we want to reach;
--- walls, water and other mons are skipped.
local function bfsPath(startX, startY, goals, isFree, maxNodes)
  local key = function(x, y) return x .. "," .. y end
  local goal = {}
  for _, c in ipairs(goals) do goal[key(c[1], c[2])] = true end
  local queue = { { startX, startY } }
  local seen = { [key(startX, startY)] = true }
  local prev = {}
  local head, nodes = 1, 0
  local DIRS4 = { { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }
  while head <= #queue and nodes < maxNodes do
    local cur = queue[head]; head = head + 1; nodes = nodes + 1
    for _, d in ipairs(DIRS4) do
      local nx, ny = cur[1] + d[1], cur[2] + d[2]
      local k = key(nx, ny)
      if not seen[k] then
        local isGoal = goal[k] == true
        if isGoal or isFree(nx, ny) then
          seen[k] = true
          prev[k] = key(cur[1], cur[2])
          if isGoal then
            local path, c = { k }, k
            while prev[c] do c = prev[c]; table.insert(path, 1, c) end
            local step = path[2] or path[1]
            local fx, fy = step:match("(-?%d+),(-?%d+)")
            if fx then return tonumber(fx) - startX, tonumber(fy) - startY end
            return nil
          end
          queue[#queue + 1] = { nx, ny }
        end
      end
    end
  end
  return nil
end

VisibleWild._bfsPath = bfsPath

local function bfsStep(game, entry, goals, px, py, maxNodes)
  return bfsPath(entry.cellX, entry.cellY, goals,
    function(x, y) return canStand(game, entry, x, y, px, py) end, maxNodes)
end

local function adjacentCells(px, py)
  return {
    { px, py - 1 }, { px, py + 1 }, { px - 1, py }, { px + 1, py },
  }
end

--- Chase / flee / approach all reduce or grow the distance one tile at a
--- time, preferring the longer axis; chase and approach walk the long way
--- round when the direct step is blocked.
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
  if away then return false end
  -- Blocked: look for a way round (walls, water, other mons).
  local goals = (distToPlayer(entry, px, py) > 1) and { { px, py } } or adjacentCells(px, py)
  local sdx, sdy = bfsStep(game, entry, goals, px, py, 96)
  if sdx and sdy then
    if owner.log then
      owner.log:info("VWLOG pathfind %s at %d,%d step %d,%d", tostring(entry.species),
        entry.cellX, entry.cellY, sdx, sdy)
    end
    return tryStep(game, entry, sdx, sdy, speed, px, py)
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

--- Grass under the feet reacts to the mon arriving or leaving.
local function rustleAt(x, y)
  local C = rt("src.core.game3.collision")
  if not (C and C.isGrass and C.isGrass(x, y)) then return end
  local FE = rt("src.core.game3.field_effects")
  if FE and FE.tallGrassAt then pcall(FE.tallGrassAt, x, y, false) end
end

local function playSe(name)
  local A = rt("src.core.game3.audio")
  local SE = rt("src.core.game3.se_ids")
  if A and A.playSe and SE and SE[name] then pcall(A.playSe, SE[name]) end
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
    -- The battle never started: keep the mon rather than deleting it, and
    -- do not try again immediately (the field may still be busy).
    entry.battleCooldown = now() + 2
    entry.nextMoveAt = now() + 2
  end
end

--- Advance the encounter sequence.  Returns true when the entry is gone.
local removeEntry  -- defined below; advanceEncounter removes entries too
local kill         -- defined below; the encounter sequence despawns through it

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

  if phase ~= "battle" then return false end

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
      owner.log:info("VWLOG battle %s dex %s lv%d at %d,%d after %.2fs", tostring(entry.species),
        tostring(entry.dex), entry.level, entry.cellX, entry.cellY,
        now() - (entry.encounterAt or now()))
    end
    kill(entry)
    if busyEntry == entry then busyEntry = nil end
    -- The map refills on expansion's ramp instead of on the same frame.
    spawnAt = now() + refillDelay()
    return false
  end
  if owner.log then
    owner.log:info("VWLOG battle failed %s: %s", tostring(entry.species), tostring(err))
  end
  finishEncounter(entry, true)
  return false
end

--- Idle/active behaviour for one mon that is not in an encounter sequence.
local function stepBehaviour(entry, game, px, py, P)
  if entry.vanishAt then return end
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
  -- approach: keep one tile of distance, face the player otherwise, and hop
  -- now and then like an excited wild mon
  if distToPlayer(entry, px, py) <= 1 then
    faceTowards(entry, px, py)
    if not entry.hopStart and math.random(5) == 1 then
      entry.hopStart = now()
      if owner.log then
        owner.log:info("VWLOG hop %s at %d,%d", tostring(entry.species), entry.cellX, entry.cellY)
      end
    end
    entry.nextMoveAt = now() + 0.6
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
  local kind = spawnKind()
  local pick, roamerMon
  if kind == "land" and owner.roamerFor then
    local okR, mon = pcall(owner.roamerFor, mapId)
    if okR and type(mon) == "table" then
      pick = { species = mon.species, level = mon.level }
      roamerMon = mon
    end
  end
  pick = pick or pickSlot(mapId, kind)
  if not pick then return false end
  -- Wild Repel: a mon below the lead's level never appears (and existing ones
  -- are cleared in update).
  local H = (rt("src.core.game3.encounters") or {})._h
  if H and H.repel_active and H.repel_active() and H.wild_level_allowed_by_repel
      and not H.wild_level_allowed_by_repel(pick.level) then
    return false
  end
  local P = playerOf()
  if not (P and P.cellX) then return false end
  local px, py = P.cellX, P.cellY
  local nearest = (kind == "land") and NEAREST or WATER_NEAREST
  -- Every legal cell in the window, then one at random.  Picking 60 random
  -- cells missed the whole window when only a couple are legal (underwater
  -- corridors are two tiles wide), which looked like "nothing ever spawns".
  local spots = {}
  for cy = py - RANGE_Y, py + RANGE_Y do
    for cx = px - RANGE_X, px + RANGE_X do
      local d = math.max(math.abs(cx - px), math.abs(cy - py))
      if d >= nearest and not occupied(cx, cy) then
        local C = rt("src.core.game3.collision")
        local elev = 3
        if kind ~= "land" and C and C.elevationAt then elev = C.elevationAt(cx, cy) or 1 end
        if wildGround(cx, cy, kind) and passable(game, cx, cy, px, py, elev) then
          spots[#spots + 1] = { x = cx, y = cy, elevation = elev }
        end
      end
    end
  end
  if #spots == 0 then return false end
  local chosen = spots[math.random(#spots)]
  local x, y, elevation = chosen.x, chosen.y, chosen.elevation
  local id = owner.world:spawnNpc(mapId, {
    x = x, y = y, elevation = elevation, facing = "down",
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
          local pid = roamerMon and roamerMon.personality
            or (Rng and Rng.Random32 and Rng.Random32()) or math.random(0, 0xFFFFFFFF)
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
            cellX = x, cellY = y, facing = "down", kind = kind, elevation = elevation,
            terrain = (rt("src.core.game3.collision") or {}).behavior
              and rt("src.core.game3.collision").behavior(x, y) or nil,
            px = x * 16, py = y * 16,
            nextMoveAt = now() + IDLE_MIN + math.random() * (IDLE_MAX - IDLE_MIN),
            localId = added and added.localId or nil,
            def = added,
            behaviour = BEHAVIOURS[behaviour],
            behaviourName = behaviour,
            pid = pid,
            gender = gender,
            roamer = roamerMon and true or nil,
            appearAt = now(),
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
          rustleAt(x, y)
          if entry.shiny then
            local okA, Audio = pcall(require, "src.core.game3.audio")
            local okS, SE = pcall(require, "src.core.game3.se_ids")
            if okA and Audio and Audio.playSe and okS and SE and SE.SE_SHINY then
              pcall(Audio.playSe, SE.SE_SHINY)
            end
          end
          if owner.log then
            owner.log:info("visible wild: internal %s (dex %s) lv%d at %d,%d (%s, npc %s, %s)",
              tostring(pick.species), tostring(entry.dex), pick.level, x, y, kind,
              tostring(added and added.localId), behaviour)
          end
          return true
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
    if not e.vanishAt and e.cellX == x and e.cellY == y then return e end
    if e.moving and e.prevX == x and e.prevY == y then return e end
  end
end

--- The entry that belongs to a runtime object, for interaction hooks.
function VisibleWild.byLocalId(localId)
  for _, e in ipairs(entries) do
    if e.localId == localId then return e end
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
  -- A battle already running means the field is not ours to lock.
  if entry.battleCooldown and now() < entry.battleCooldown then return true end
  local okB, Battle = pcall(require, "src.core.game3.battle")
  if okB and Battle and Battle.isActive and Battle.isActive() then return true end
  if busyEntry and busyEntry ~= entry then return true end
  local P = playerOf()
  if P and P.cellX then faceTowards(entry, P.cellX, P.cellY) end
  busyEntry = entry
  entry.phase, entry.phaseAt = "notice", now()
  entry.encounterAt = now()
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

--- A mon the ambient-cry task can borrow its voice from: on screen and not
--- already leaving.
function VisibleWild.cryCandidate()
  local P = playerOf()
  if not (P and P.cellX) then return nil end
  local pool = {}
  for _, e in ipairs(entries) do
    if not e.vanishAt and math.abs(e.cellX - P.cellX) <= 10
        and math.abs(e.cellY - P.cellY) <= 8 then
      pool[#pool + 1] = e
    end
  end
  if #pool == 0 then return nil end
  return pool[math.random(#pool)]
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

  -- Water encounters do not follow the player ashore.
  if spawnKind() == "land" then
    for i = #entries, 1, -1 do
      local e = entries[i]
      if not e.vanishAt and e.kind and e.kind ~= "land" then kill(e) end
    end
  end

  -- Repel also clears what is already out there.
  local H = (rt("src.core.game3.encounters") or {})._h
  if H and H.repel_active and H.repel_active() and H.wild_level_allowed_by_repel then
    for i = #entries, 1, -1 do
      local e = entries[i]
      if not e.vanishAt and not e.phase and not H.wild_level_allowed_by_repel(e.level) then
        if owner.log then
          owner.log:info("VWLOG repel %s lv%d at %d,%d", tostring(e.species), e.level,
            e.cellX, e.cellY)
        end
        kill(e)
      end
    end
  end

  for i = #entries, 1, -1 do
    local e = entries[i]
    if e.stepAnim and e.stepAnim > 0 then e.stepAnim = e.stepAnim - 1 end
    if e.hopStart and now() - e.hopStart >= HOP_SECONDS then e.hopStart = nil end
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
        e.prevX, e.prevY = nil, nil
        e.px, e.py = e.targetPx, e.targetPy
        if e.eo then e.eo.px, e.eo.py = e.px, e.py end
        if not e.active and not e.phase then
          e.nextMoveAt = now() + IDLE_MIN + math.random() * (IDLE_MAX - IDLE_MIN)
        end
      end
    end
    if e.vanishAt and now() - e.vanishAt >= VANISH_SECONDS then
      removeEntry(e)
      table.remove(entries, i)
      if busyEntry == e then busyEntry = nil end
    elseif not e.attached or not (e.eo and e.eo.draw) then
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
    if (e.phase and not e.vanishAt) or (busyEntry == e and not e.vanishAt) then
      if advanceEncounter(e, game, px, py) then table.remove(entries, i) end
    elseif not e.shiny and (math.abs(e.cellX - px) > FORGET or math.abs(e.cellY - py) > FORGET) then
      if owner.log then
        owner.log:info("VWLOG forget %s lv%d at %d,%d (player %d,%d)",
          tostring(e.species), e.level, e.cellX, e.cellY, px, py)
      end
      kill(e)
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
    -- One at a time, on expansion's ramp: an empty map fills quickly, a busy
    -- one slowly.  A failed attempt (map still loading) retries next update.
    if spawnOne(game, mapId) then
      spawnAt = now() + refillDelay()
    else
      -- No legal tile right now (underwater corridors, a full window): try
      -- again shortly instead of every frame.
      spawnAt = now() + 0.25
    end
  end
end

--- Play the despawn animation, then take the mon off the map.  Map changes
--- call removeEntry directly: there is nothing left to look at.
kill = function(entry)
  if not entry then return end
  if entry.vanishAt then return end
  entry.vanishAt = now()
  rustleAt(entry.cellX, entry.cellY)
  playSe("SE_FLEE")
end

--- An NPC walked into this mon.  Expansion removes a generated OWE instead
--- of letting it block the NPC, so the same happens here.
function VisibleWild.bump(entry)
  if not entry then return end
  for i, e in ipairs(entries) do
    if e == entry then
      if owner.log then
        owner.log:info("VWLOG bumped away %s lv%d at %d,%d", tostring(e.species),
          e.level, e.cellX, e.cellY)
      end
      kill(e)
      if busyEntry == e then busyEntry = nil end
      spawnAt = now() + refillDelay()
      return
    end
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
