-- Very subtle screen-space marking of the area outside the pilot's awareness.
-- The world itself stays readable; only the unknown area is darkened slightly.

local C = require("shared.constants")
local Vision = require("shared.vision")

local VisionOverlay = {}

-- Half-resolution mask drawn back at 2x with linear filtering. That gives the
-- shadow edge a soft pixel-art falloff instead of a razor-thin raycast line.
local W, H = 320, 180
local mask

local function ensureMask()
  if not mask then
    mask = love.graphics.newCanvas(W, H)
    mask:setFilter("linear", "linear")
  end
end

function VisionOverlay.draw(viewer, camera, clouds)
  if not viewer or not camera then return end
  ensureMask()
  local scale = C.WORLD.scale * 0.5
  local camX = math.floor(camera.x)
  local camY = math.floor(camera.y)
  local world = Vision.outline(viewer, clouds, 320)
  local pts = {}
  for i = 1, #world, 2 do
    pts[#pts + 1] = (world[i] - camX) * scale
    pts[#pts + 1] = (world[i + 1] - camY) * scale
  end

  local previous = love.graphics.getCanvas()
  love.graphics.setCanvas(mask)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.setBlendMode("alpha")
  love.graphics.setColor(0.012, 0.022, 0.030, 0.10)
  love.graphics.rectangle("fill", 0, 0, W, H)
  love.graphics.setBlendMode("replace")
  love.graphics.setColor(0, 0, 0, 0)
  love.graphics.polygon("fill", pts)
  love.graphics.setBlendMode("alpha")
  love.graphics.setCanvas(previous)

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(mask, 0, 0, 0, 2, 2)
end

return VisionOverlay
