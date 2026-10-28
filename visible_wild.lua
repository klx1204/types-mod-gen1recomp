-- Visible wild encounters: a few of the map's own wild Pokemon walk its
-- encounter tiles as 32x32 party icons.  Touching one starts its battle;
-- random encounters stay off while any are allowed to exist.
--
-- Modelled on emerald-3ds-fairy's visible wild patch: one is added every two
-- seconds up to the setting's count, a defeated one disappears on its own,
-- and leaving the map clears the lot.

local VisibleWild = {}

local MAX = 6
local COUNTS = { 0, 2, 4, 6 }        -- OFF / FEW / SOME / MANY
local RANGE_X, RANGE_Y = 11, 6       -- spawn window, in tiles
local NEAREST = 3                    -- never closer than this
local FORGET = 15                    -- gone beyond this many tiles
local SPAWN_SECONDS = 2
local WALK_MIN, WALK_MAX = 40, 160   -- frames of standing still

function VisibleWild.count(index)
  return COUNTS[tonumber(index) or 1] or 0
end

local entries = {}
local currentMap
local spawnAt = 0
local uid = 0
local owner = nil

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
    local ok = C.canEnter(game, x, y, {
      fromX = fromX or x, fromY = fromY or y, dir = dir,
      elevation = 3,
    })
    if ok == false then return false end
  end
  return true
end

-- Spawning and wandering both stay on tiles the map lists as wild ground, so
-- an icon never stands on a path or a rooftop.
local function wildGround(x, y)
  local E = rt("src.core.game3.encounters")
  if not (E and E.terrainAt) then return true end
  local terrain = E.terrainAt(x, y)
  return terrain == "land"
end

local function monPicture(species, shiny, back)
  local P = rt("src.core.game3.pokemon")
  if not P then return nil end
  local fn = back and P.backPic or P.frontPic
  if type(fn) ~= "function" then return nil end
  local ok, entry = pcall(fn, species, nil, shiny)
  return ok and entry or nil
end

local function painter(entry)
  return function(self, camX, camY)
    local P = rt("src.core.game3.pokemon")
    local icon = P and P.icon and P.icon(entry.species)
    if not (icon and icon.image) then
      if owner.log then owner.log:info("visible wild: no icon for %s", tostring(entry.species)) end
      return
    end
    local q = icon.quads and (icon.quads[0] or icon.quads[1])
    local sx = (self.x or 0) - (camX or 0) - 8
    local sy = (self.y or 0) - (camY or 0) - 16
    love.graphics.setBlendMode("alpha")
    love.graphics.setColor(1, 1, 1, 1)
    -- Up/down use the battle art (64x64 scaled to 32); left/right flip the
    -- party icon, which reads better than a front picture sliding sideways.
    local facing = entry.facing or "down"
    local drawn = false
    if facing == "up" or facing == "down" then
      local pic = monPicture(entry.species, entry.shiny, facing == "up")
      if pic and pic.image then
        love.graphics.draw(pic.image, sx, sy, 0, 0.5, 0.5)
        drawn = true
      end
    end
    if not drawn then
      local flip = facing == "left" and -1 or 1
      local ox = flip < 0 and 32 or 0
      if q then
        love.graphics.draw(icon.image, q, sx + ox, sy, 0, flip, 1)
      else
        love.graphics.draw(icon.image, sx + ox, sy, 0, flip, 1)
      end
    end
    if entry.shiny then
      -- Four sparkles orbiting the icon, emerald-3ds-fairy's idea without
      -- needing a particle sprite.
      local t = now()
      for i = 1, 4 do
        local a = t * 2.2 + i * math.pi / 2
        local r = 17 + math.sin(t * 5 + i) * 3
        local px = sx + 16 + math.cos(a) * r
        local py = sy + 16 + math.sin(a) * r * 0.55
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

local function spawnOne(game, mapId)
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
        })
        if id then
          local Objects = rt("src.core.game3.objects")
          local defs = Objects and Objects.runtimeByMap and Objects.runtimeByMap[mapId]
          local added = defs and defs[#defs]
          uid = uid + 1
          local entry = {
            uid = uid, npcId = id, species = pick.species, level = pick.level,
            cellX = x, cellY = y, facing = "down", idle = math.random(WALK_MIN, WALK_MAX),
            localId = added and added.localId or nil,
            def = added,
            shiny = owner.isShiny and owner.isShiny() or false,
          }
          entries[#entries + 1] = entry
          if not attach(entry) then
            -- Without a painter the event falls back to graphics id 0, which
            -- is the player character in FireRed.  Drop it rather than let a
            -- Brendan clone wander the map.
            removeEntry(entry)
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
            owner.log:info("visible wild: %s lv%d at %d,%d (npc %s, def %s)",
              tostring(pick.species), pick.level, x, y, tostring(id), tostring(added and added.localId))
          end
          return true
        end
      end
    end
  end
  return false
end

local function removeEntry(entry)
  if entry.npcId and owner.world and owner.world.removeNpc then
    pcall(function() owner.world:removeNpc(entry.npcId) end)
  end
end

function VisibleWild.clear()
  for _, e in ipairs(entries) do removeEntry(e) end
  entries = {}
  spawnAt = now() + SPAWN_SECONDS
end

function VisibleWild.most()
  return VisibleWild.count(owner.setting and owner.setting() or 1)
end

function VisibleWild.at(x, y)
  for _, e in ipairs(entries) do
    if e.cellX == x and e.cellY == y then return e end
  end
end

--- Called once per player step.
function VisibleWild.update()
  local s = session()
  local mapId = s and s.map
  if mapId ~= currentMap then
    currentMap = mapId
    VisibleWild.clear()
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
    if not e.attached then attach(e) end
    if math.abs(e.cellX - px) > FORGET or math.abs(e.cellY - py) > FORGET then
      removeEntry(e)
      table.remove(entries, i)
    elseif e.idle and e.idle > 0 then
      e.idle = e.idle - 1
    else
      local dir = math.random(4)
      local dx = (dir == 3 and 1) or (dir == 4 and -1) or 0
      local dy = (dir == 1 and -1) or (dir == 2 and 1) or 0
      local tx, ty = e.cellX + dx, e.cellY + dy
      if tx ~= px or ty ~= py then
        if not occupied(tx, ty) and wildGround(tx, ty) and passable(game, tx, ty, e.cellX, e.cellY) then
          e.cellX, e.cellY = tx, ty
          e.facing = (dx > 0 and "right") or (dx < 0 and "left")
            or (dy > 0 and "down") or "up"
          if e.def then e.def.x, e.def.y = tx, ty end
          if e.eo then
            e.eo.x, e.eo.y = tx * 16, ty * 16
            e.eo.cellX, e.eo.cellY = tx, ty
            e.eo.px, e.eo.py = tx * 16, ty * 16
          end
        end
      end
      e.idle = math.random(WALK_MIN, WALK_MAX)
    end
  end

  if #entries < most and now() >= spawnAt then
    spawnAt = now() + SPAWN_SECONDS
    spawnOne(game, mapId)
  end
end

function VisibleWild.remove(entry)
  if not entry then return end
  for i, e in ipairs(entries) do
    if e == entry then
      removeEntry(e)
      table.remove(entries, i)
      return
    end
  end
end

function VisibleWild.setup(mod, opts)
  owner = {
    world = mod.world,
    setting = opts.setting,
    isShiny = opts.isShiny,
    objects = nil,
    log = opts.log,
  }
  return VisibleWild
end

return VisibleWild
