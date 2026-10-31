-- Follower: the lead Pokemon of the party walks behind the player, using the
-- mod's own overworld sheets (the 386 Gen 3 ones shipped for visible wild).
--
-- The engine already has the trail logic (src/world/game3/Follower.lua): it
-- records the cells the player walked through and steps the companion there.
-- What it has no opinion about is *what* the companion is and what it looks
-- like, so this module supplies both, and its dialogue.

local Follower = {}

local owner = nil
local sprites = nil
local state = { species = nil, sprite = nil, npc = nil, appearAt = nil }

-- pret DoJumpSpriteMovement y2 for a normal/low ledge hop: 16 entries over
-- 32 frames, the same curve the player's own jump uses.
local JUMP_Y = { -2, -4, -6, -8, -9, -10, -10, -10, -9, -8, -6, -5, -3, -2, 0, 0 }

-- Poké Ball that the companion comes out of when it (re)appears.
local BALL_SECONDS = 0.45
local BOB_SECONDS = 8 / 60            -- pret bobs one pixel every 8 frames

local function now()
  return love and love.timer and love.timer.getTime and love.timer.getTime() or os.clock()
end

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

local function enabled()
  if owner and owner.enabled then
    local ok, v = pcall(owner.enabled)
    return ok and v ~= false
  end
  return true
end

--- The first party member that can walk: alive, not an egg (pret
--- GetFirstLiveMon).  Not simply slot 1 -- a fainted lead stays in the party.
local function lead()
  local s = session()
  local party = s and s.party
  if type(party) ~= "table" then return nil end
  for i = 1, 6 do
    local mon = party[i]
    if type(mon) == "table" and not (mon.isEgg or mon.egg) then
      local hp = tonumber(mon.hp) or tonumber(mon.currentHp)
      if hp == nil or hp > 0 then
        local species = tonumber(mon.species or mon.speciesId)
        if species then return species, mon end
      end
    end
  end
  return nil
end

local function nameOf(species)
  local P = rt("src.core.game3.pokemon")
  local name = P and P._names and P._names[species]
  return name or "它"
end

--- Shown on foot only: riding the water or diving leaves it behind, and an
--- empty party or an egg has nothing to follow.
local function shouldShow(_game, world)
  if not enabled() then return false end
  local P = world and world.player
  if not P then return false end
  if P.underwater or P.surfing then return false end
  return lead() ~= nil
end

local function drawBall(cx, cy, elapsed)
  local t = math.min(1, elapsed / (BALL_SECONDS * 0.6))
  if t >= 1 then return end
  local r = 7 * (1 - t)
  if r < 0.6 then return end
  love.graphics.setColor(0.92, 0.92, 0.92, 1)
  love.graphics.circle("fill", cx, cy, r)
  love.graphics.setColor(0.85, 0.22, 0.22, 1)
  love.graphics.arc("fill", cx, cy, r, math.pi, math.pi * 2)
  love.graphics.setColor(0.15, 0.15, 0.15, 1)
  love.graphics.rectangle("fill", cx - r, cy - 1, r * 2, 2)
  love.graphics.setColor(1, 1, 1, 1)
end

local function newSprite()
  return {
    draw = function(_, x, y, camX, camY, facing, walkPhase)
      local species = state.species
      if not species or not sprites then return end
      local img = sprites.owImage(species)
      if not img then return end
      local frame
      if facing == "up" then
        frame = (walkPhase == 1) and 3 or 2
      elseif facing == "left" or facing == "right" then
        frame = (walkPhase == 1) and 5 or 4
      else
        frame = (walkPhase == 1) and 1 or 0
      end
      local SX = (x or 0) - (camX or 0) - 8
      local SY = (y or 0) - (camY or 0) - 16

      local npc = owner and owner.engine and owner.engine.current and owner.engine.current()
      -- Ledge hops arc like the player's: the engine moves the companion two
      -- cells, this lifts it over the edge.
      if npc and npc.jumping and npc.moving then
        local idx = math.floor(((npc.progress or 1) - 1) / 2)
        if idx >= 0 then SY = SY + (JUMP_Y[idx + 1] or 0) end
      end
      -- OW_FOLLOWERS_BOBBING: one pixel every eighth frame while idle.
      if npc and not npc.moving then
        local phase = math.floor(now() / BOB_SECONDS) % 8
        if phase == 2 then SY = SY - 1 end
      end

      local alpha = 1
      local elapsed = state.appearAt and (now() - state.appearAt) or BALL_SECONDS
      if elapsed < BALL_SECONDS then
        -- OW_FOLLOWERS_POKEBALLS: the ball pops and the mon fades out of it.
        alpha = math.max(0, math.min(1, (elapsed - BALL_SECONDS * 0.35) / (BALL_SECONDS * 0.4)))
        if alpha <= 0 then
          drawBall(SX + 16, SY + 16, elapsed)
          return
        end
      end

      local flip = facing == "right" and -1 or 1
      love.graphics.setBlendMode("alpha")
      love.graphics.setColor(1, 1, 1, alpha)
      love.graphics.draw(img, sprites.owQuad(img, frame),
        SX + (flip < 0 and 32 or 0), SY, 0, flip, 1)
      if elapsed < BALL_SECONDS then
        drawBall(SX + 16, SY + 16, elapsed)
      end
      love.graphics.setColor(1, 1, 1, 1)
    end,
  }
end

--- One line, picked from how the mon is doing.  Kept short on purpose: the
--- HGSS message table is ~120 lines and does not fit this mod's scope.
local function pick(list)
  return list[math.random(#list)]
end

--- One line.  Conditions are checked in order, like pret's message table:
--- a poisoned mon does not say it is happy behind you.
local function talkText(species, mon)
  local name = nameOf(species)

  local status = mon and mon.status
  if type(status) == "table" then status = status.id or status.kind end
  if status ~= nil and status ~= 0 and status ~= "NONE" then
    return pick({ name .. "看起来有点不舒服。", name .. "有气无力地挪着步子。" })
  end

  local hp = tonumber(mon and (mon.hp or mon.currentHp))
  local maxHp = tonumber(mon and mon.maxHp)
  if hp and maxHp and maxHp > 0 and hp / maxHp <= 0.25 then
    return name .. "受了伤，跟得很吃力。"
  end

  local item = tonumber(mon and (mon.item or mon.heldItem))
  if item and item ~= 0 and math.random(3) == 1 then
    return name .. "嘴里叼着东西跟着你。"
  end

  local P = rt("src.core.game3.pokemon")
  local friendship = (P and P.friendshipOf and P.friendshipOf(mon)) or 70
  if friendship >= 200 then
    return pick({ name .. "亲昵地蹭了蹭你。", name .. "开心地绕着你转了一圈。" })
  elseif friendship >= 100 then
    return pick({ name .. "高兴地跟在你身后。", name .. "走两步就回头看看你。" })
  elseif friendship >= 50 then
    return pick({ name .. "安静地跟在你后面。", name .. "不紧不慢地迈着步子。" })
  end
  return pick({ name .. "好像有点不情愿地跟着。", name .. "和你保持了半步距离。" })
end

--- The species currently being drawn (for tests and other mods).
function Follower.species() return state.species end

--- Called from the engine when the player presses A facing the companion.
function Follower.talk()
  local species, mon = lead()
  if not species then return false end
  local Field = rt("src.core.game3.field")
  local Message = rt("src.ui.game3.message")
  if not (Field and Message and Message.show) then return false end
  if Message.isOpen and Message.isOpen() then return false end
  local token = {}
  local text = talkText(species, mon)
  local opened = false
  if Field.lock then Field.lock(token) end
  local ok = pcall(function()
    Message.show(text, function()
      if Field.unlock then Field.unlock(token) end
    end)
    opened = true
  end)
  if not ok or not opened then
    if Field.unlock then Field.unlock(token) end
    return false
  end
  if owner and owner.log then
    owner.log:info("follower talk: %s", text)
  end
  return true
end

--- Wire into the engine's follower module.
function Follower.setup(mod, opts)
  opts = opts or {}
  -- The engine module is looked up by the caller: this file is also loaded by
  -- the smoke test, where there is no engine to find.
  local F = opts.engine
  if not F then return nil end
  owner = { mod = mod, log = mod.log, engine = F, enabled = opts.enabled }
  sprites = opts.sprites or nil
  -- Handle for other mods/tests ("is the follower drawing, and as what").
  F.visibleFollower = Follower
  if F.setShouldSpawn then F.setShouldSpawn(shouldShow) end
  if not F._visibleWildFollower then
    F._visibleWildFollower = true
    local originalUpdate = F.update
    F.update = function(game, ...)
      originalUpdate(game, ...)
      local species = lead()
      state.species = species
      local npc = F.current and F.current()
      if npc ~= state.npc then
        state.npc = npc
        if npc then state.appearAt = now() end
      end
      if npc and species then
        if not npc.sprite then
          npc.sprite = newSprite()
          state.sprite = npc.sprite
        end
        npc.hidden = false
        -- A move of two or more cells is a ledge hop: give it the player's
        -- jump length and draw the arc (the engine would walk it through the
        -- ledge at double speed).
        if npc.moving and npc.targetX then
          local dist = math.abs(npc.targetX - npc.cellX) + math.abs(npc.targetY - npc.cellY)
          if dist >= 2 then
            npc.jumping = true
            npc.stepFrames = 32
          else
            npc.jumping = false
          end
        else
          npc.jumping = false
        end
      end
    end
    local originalTalk = F.talk
    F.talk = function()
      if Follower.talk() then return true end
      if originalTalk then return originalTalk() end
      return false
    end
  end
  return Follower
end

return Follower
