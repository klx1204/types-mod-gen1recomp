-- Load main.lua with a fake mod host. This catches syntax errors and missing
-- API calls without an engine checkout, a ROM or generated data.
local root = "."

local Types = {
  useOverlay = function() end,
  clearOverlay = function() end,
  name = function(id) return tostring(id) end,
}
package.preload["src.core.game3.battle.types"] = function() return Types end

local hooks, events = {}, {}
local store = {}

local function readFile(rel)
  local f = io.open(root .. "/" .. rel, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local mod = {
  path = root,
  log = {
    info = function() end,
    warn = function() end,
    error = function() end,
  },
  save = {
    get = function(_, key, default) return store[key] ~= nil and store[key] or default end,
    set = function(_, key, value) store[key] = value end,
  },
  hooks = {
    wrap = function(_, name, fn) hooks[name] = fn end,
  },
  events = {
    on = function(_, name, fn) events[name] = fn end,
  },
  content = {
    moves = { register = function() end },
  },
  ui = {},
}

function mod:read(rel)
  return readFile(rel)
end

local chunk = assert(loadfile(root .. "/main.lua"))
local entry = assert(chunk(), "main.lua must return a function")
assert(type(entry) == "function", "main.lua must return a function")
entry(mod)

assert(type(hooks["ui.options.rows"]) == "function", "ui.options.rows hook missing")
assert(type(hooks["battle.catch_exp"]) == "function", "battle.catch_exp hook missing")
assert(type(hooks["battle.exp_award"]) == "function", "battle.exp_award hook missing")
assert(type(hooks["fieldmove.eligibility"]) == "function", "fieldmove.eligibility hook missing")
assert(type(hooks["item.use"]) == "function", "item.use hook missing")
assert(type(events["game.ready"]) == "function", "game.ready event missing")
assert(type(events["save.loaded"]) == "function", "save.loaded event missing")

print("main_smoke_test: ok")
