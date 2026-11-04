-- Tiny deterministic LCG. Used for procedural clouds and pickup placement so
-- the server and every client generate identical content from one seed.
-- Multiplication stays below 2^53, so it is exact in Lua 5.1 / LuaJIT.

local Rng = {}
Rng.__index = Rng

function Rng.new(seed)
  seed = math.floor(tonumber(seed) or 1) % 4294967296
  if seed < 0 then seed = seed + 4294967296 end
  if seed == 0 then seed = 2463534242 end
  return setmetatable({ state = seed }, Rng)
end

function Rng:next()
  self.state = (1664525 * self.state + 1013904223) % 4294967296
  return self.state / 4294967296
end

function Rng:range(a, b)
  return a + self:next() * (b - a)
end

function Rng:int(a, b)
  return math.floor(a + self:next() * (b - a + 1))
end

function Rng:chance(p)
  return self:next() < p
end

function Rng:pick(list)
  return list[self:int(1, #list)]
end

return Rng
