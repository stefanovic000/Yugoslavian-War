-- Solid old-town building strips at the left and right edges of the arena.
-- The simulation treats these as crash boundaries; this module draws the
-- facades inside the camera view.

local C = require("shared.constants")

local Walls = {}

local W, H = C.WORLD.w, C.WORLD.h
local LEFT, RIGHT = C.WORLD.wallLeft, C.WORLD.wallRight

local function windows(x, y, width, cols, rows)
  love.graphics.setColor(0.075, 0.070, 0.050, 1)
  for row = 0, rows - 1 do
    for col = 0, cols - 1 do
      local wx = x + 5 + col * 11
      local wy = y + 6 + row * 13
      if (col + row) % 3 == 0 then
        love.graphics.setColor(0.48, 0.40, 0.22, 0.85)
      else
        love.graphics.setColor(0.055, 0.065, 0.065, 1)
      end
      love.graphics.rectangle("fill", wx, wy, 5, 7)
    end
  end
end

local function facade(x, width, side)
  love.graphics.setColor(0.185, 0.165, 0.120, 1)
  love.graphics.rectangle("fill", x, 0, width, C.WORLD.groundY)
  love.graphics.setColor(0.245, 0.215, 0.150, 1)
  love.graphics.rectangle("fill", x, 0, 5, C.WORLD.groundY)
  love.graphics.setColor(0.090, 0.080, 0.060, 1)
  for y = 24, C.WORLD.groundY, 34 do
    love.graphics.rectangle("fill", x, y, width, 2)
  end
  windows(x, 8, width, 3, 10)

  -- roof edge, chimney and a couple of old-town roof steps
  love.graphics.setColor(0.120, 0.105, 0.075, 1)
  love.graphics.rectangle("fill", x - (side == "left" and 0 or 6), 0, width + 6, 8)
  love.graphics.setColor(0.230, 0.200, 0.140, 1)
  love.graphics.rectangle("fill", x + 6, 10, 8, 22)
  love.graphics.setColor(0.070, 0.060, 0.045, 1)
  love.graphics.rectangle("fill", x + 6, 0, 8, 5)

  -- cracks and soot
  love.graphics.setColor(0.075, 0.070, 0.052, 0.8)
  for i = 1, 6 do
    local cx = x + 8 + (i * 9) % (width - 12)
    local cy = 45 + (i * 37) % (C.WORLD.groundY - 60)
    love.graphics.rectangle("fill", cx, cy, 1, 8 + (i % 3) * 5)
  end
end

function Walls.draw()
  facade(0, LEFT, "left")
  facade(RIGHT, W - RIGHT, "right")
end

return Walls
