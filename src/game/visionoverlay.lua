-- Very subtle screen-space marking of the area outside the pilot's awareness.
-- The world itself stays readable; only the unknown area is darkened slightly.

local C = require("shared.constants")
local Vision = require("shared.vision")

local VisionOverlay = {}

local W, H = 640, 360
local mask

local function ensureMask()
  if not mask then
    mask = love.graphics.newCanvas(W, H)
    mask:setFilter("nearest", "nearest")
  end
end

function VisionOverlay.draw(viewer, camera)
  if not viewer or not camera then return end
  ensureMask()
  local scale = C.WORLD.scale
  local world = Vision.outline(viewer, 64)
  local pts = {}
  for i = 1, #world, 2 do
    pts[#pts + 1] = (world[i] - camera.x) * scale
    pts[#pts + 1] = (world[i + 1] - camera.y) * scale
  end

  -- Build a transparent hole for the visible area, then composite the dark
  -- outside over the world. This avoids relying on a stencil-capable canvas.
  local previous = love.graphics.getCanvas()
  love.graphics.setCanvas(mask)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.setBlendMode("alpha")
  love.graphics.setColor(0.012, 0.022, 0.030, 0.12)
  love.graphics.rectangle("fill", 0, 0, W, H)
  love.graphics.setBlendMode("replace")
  love.graphics.setColor(0, 0, 0, 0)
  love.graphics.polygon("fill", pts)
  love.graphics.setBlendMode("alpha")
  love.graphics.setCanvas(previous)

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(mask, 0, 0)
  love.graphics.setColor(0.58, 0.66, 0.58, 0.10)
  love.graphics.setLineWidth(1)
  love.graphics.polygon("line", pts)
end

return VisionOverlay
