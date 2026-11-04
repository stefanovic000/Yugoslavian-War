-- Low ground strip at the bottom of the arena. It is drawn in world
-- coordinates; the authoritative simulation kills a plane that touches it.

local C = require("shared.constants")

local Ground = {}

local W, H = C.WORLD.w, C.WORLD.h
local TOP = C.WORLD.groundY

local function ridge(x, base, amp, phase)
  return base + math.sin(x * 0.035 + phase) * amp
    + math.sin(x * 0.091 + phase * 2) * amp * 0.35
end

function Ground.draw()
  -- dark earth body
  love.graphics.setColor(0.115, 0.105, 0.075, 1)
  love.graphics.rectangle("fill", 0, TOP, W, H - TOP)

  -- low rolling crest, deterministic so client/server screens agree
  local points = { 0, H, 0, TOP }
  for x = 0, W, 8 do
    points[#points + 1] = x
    points[#points + 1] = math.floor(ridge(x, TOP + 2, 3, 0.3))
  end
  points[#points + 1] = W
  points[#points + 1] = H
  love.graphics.setColor(0.205, 0.235, 0.145, 1)
  love.graphics.polygon("fill", points)

  -- a thin dry-grass line and a few stones
  love.graphics.setColor(0.360, 0.350, 0.205, 1)
  for x = 0, W, 8 do
    local y = math.floor(ridge(x, TOP + 2, 3, 0.3))
    love.graphics.rectangle("fill", x, y, 7, 1)
    if math.floor(x / 8) % 7 == 0 then
      love.graphics.rectangle("fill", x + 2, y - 3, 2, 2)
    end
  end

  love.graphics.setColor(0.075, 0.070, 0.050, 1)
  for i = 1, 18 do
    local x = (i * 127) % W
    local y = TOP + 8 + (i * 37) % 20
    love.graphics.rectangle("fill", x, y, 5 + (i % 3) * 2, 2)
  end
end

return Ground
