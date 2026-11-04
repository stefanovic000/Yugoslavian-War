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

  -- Single union mask: general blind area and all cloud shadows. Everything is
  -- written as a solid mask and composited once, so overlaps never darken.
  local previous = love.graphics.getCanvas()
  love.graphics.setCanvas(mask)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.setBlendMode("alpha")
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, W, H)
  love.graphics.setBlendMode("replace")
  love.graphics.setColor(0, 0, 0, 0)
  love.graphics.polygon("fill", pts)

  if clouds then
    love.graphics.setColor(1, 1, 1, 1)
    for _, cloud in ipairs(clouds.list) do
      for _, puff in ipairs(cloud.puffs) do
        local cx = cloud.x + puff.dx
        local cy = cloud.y + puff.dy
        local rx = puff.rx or puff.r
        local ry = puff.ry or puff.r
        local a = math.atan2(cy - viewer.y, cx - viewer.x)
        local startA, endA = a - math.pi / 2, a + math.pi / 2
        local poly = {}
        local e1x, e1y, e2x, e2y
        for i = 0, 8 do
          local ang = startA + (endA - startA) * (i / 8)
          local px = cx + math.cos(ang) * rx
          local py = cy + math.sin(ang) * ry
          if i == 0 then e1x, e1y = px, py end
          if i == 8 then e2x, e2y = px, py end
          poly[#poly + 1] = (px - camX) * scale
          poly[#poly + 1] = (py - camY) * scale
        end
        local a1 = math.atan2(e1y - viewer.y, e1x - viewer.x)
        local a2 = math.atan2(e2y - viewer.y, e2x - viewer.x)
        poly[#poly + 1] = (viewer.x + math.cos(a2) * 1800 - camX) * scale
        poly[#poly + 1] = (viewer.y + math.sin(a2) * 1800 - camY) * scale
        poly[#poly + 1] = (viewer.x + math.cos(a1) * 1800 - camX) * scale
        poly[#poly + 1] = (viewer.y + math.sin(a1) * 1800 - camY) * scale
        love.graphics.polygon("fill", poly)
      end
    end
  end

  love.graphics.setBlendMode("alpha")
  love.graphics.setCanvas(previous)
  love.graphics.setColor(0.005, 0.010, 0.016, 0.09)
  love.graphics.draw(mask, 0, 0, 0, 2, 2)
end

return VisionOverlay
