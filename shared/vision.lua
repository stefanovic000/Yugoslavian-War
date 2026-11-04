-- Wide WW2-style awareness: long forward arc, shorter side arc and a shorter
-- rear arc. Aircraft behind cloud are not visible; firing can reveal a faint
-- silhouette for a moment (handled by the scenes).

local C = require("shared.constants")
local M = require("shared.mathx")
local Clouds = require("shared.clouds")

local Vision = {}
local V = C.VISION

local function rad(deg)
  return deg * math.pi / 180
end

local FRONT = rad(V.frontAngle)
local SIDE = rad(V.sideAngle)

function Vision.rangeAt(viewerAngle, targetAngle)
  local d = math.abs(M.angleDiff(viewerAngle, targetAngle))
  if d <= FRONT then return V.frontRange end
  if d <= SIDE then
    local t = (d - FRONT) / (SIDE - FRONT)
    return V.frontRange + (V.sideRange - V.frontRange) * t
  end
  local t = (d - SIDE) / (math.pi - SIDE)
  return V.sideRange + (V.rearRange - V.sideRange) * t
end

function Vision.lineOfSight(viewer, target, clouds)
  if not viewer or not target then return false end
  if Clouds.pointInside(clouds, target.x, target.y) then return false end
  return not Clouds.segmentBlocked(clouds, viewer.x, viewer.y, target.x, target.y)
end

function Vision.canSee(viewer, target, clouds)
  if not viewer or not target or not target.alive then return false end
  local dist = M.dist(viewer.x, viewer.y, target.x, target.y)
  if dist <= V.near then
    return Vision.lineOfSight(viewer, target, clouds)
  end
  local angle = math.atan2(target.y - viewer.y, target.x - viewer.x)
  if dist > Vision.rangeAt(viewer.angle, angle) then return false end
  return Vision.lineOfSight(viewer, target, clouds)
end

-- World-space outline of the awareness area, used by the subtle blind-area
-- overlay. The polygon follows the aircraft nose.
function Vision.outline(viewer, segments)
  segments = segments or 64
  local pts = {}
  for i = 0, segments - 1 do
    local a = -math.pi + (i / segments) * math.pi * 2
    local worldAngle = viewer.angle + a
    local r = Vision.rangeAt(viewer.angle, worldAngle)
    pts[#pts + 1] = viewer.x + math.cos(worldAngle) * r
    pts[#pts + 1] = viewer.y + math.sin(worldAngle) * r
  end
  return pts
end

return Vision
