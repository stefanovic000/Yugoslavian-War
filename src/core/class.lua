-- class.lua
-- Minimal single-inheritance OOP for LuaJIT / Lua 5.1.
--
--   local Plane = Class("Plane")
--   function Plane:init(x, y) self.x, self.y = x, y end
--   local p = Plane.new(10, 20)   -- calls :init automatically
--   Class.is(p, Plane)            -- true

local class = {}

local function make(name, parent)
  local c = {}
  c.__index = c
  c.__name = name
  c.super = parent

  if parent then
    setmetatable(c, { __index = parent })
  end

  c.new = function(...)
    local obj = setmetatable({}, c)
    if obj.init then
      obj:init(...)
    end
    return obj
  end

  c.__tostring = function()
    return name or "Object"
  end

  return c
end

setmetatable(class, {
  __call = function(_, name, parent)
    return make(name, parent)
  end,
})

function class.is(obj, klass)
  if type(obj) ~= "table" then return false end
  local mt = getmetatable(obj)
  while mt do
    if mt == klass then return true end
    mt = mt.super
  end
  return false
end

return class
