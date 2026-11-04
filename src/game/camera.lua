-- Smooth side-scrolling camera. It centers on a target, clamps to the walled
-- world, and never looks ahead (kept deliberately simple for 4-player fights).

local C = require("shared.constants")

local Camera = {}

local function clamp(x, lo, hi)
  return math.max(lo, math.min(hi, x))
end

function Camera.new()
  return { x = 0, y = 0, initialized = false }
end

function Camera.snap(cam, x, y)
  local w, h = C.WORLD.w, C.WORLD.h
  local vw, vh = C.WORLD.viewW, C.WORLD.viewH
  cam.x = clamp(x - vw * 0.5, 0, math.max(0, w - vw))
  cam.y = clamp(y - vh * 0.5, 0, math.max(0, h - vh))
  cam.initialized = true
end

function Camera.follow(cam, x, y, dt)
  if not cam.initialized then
    Camera.snap(cam, x, y)
    return
  end
  local w, h = C.WORLD.w, C.WORLD.h
  local vw, vh = C.WORLD.viewW, C.WORLD.viewH
  local maxX = math.max(0, w - vw)
  local maxY = math.max(0, h - vh)
  local tx = clamp(x - vw * 0.5, 0, maxX)
  local ty = clamp(y - vh * 0.5, 0, maxY)
  local k = 1 - math.exp(-9 * dt)
  cam.x = clamp(cam.x + (tx - cam.x) * k, 0, maxX)
  cam.y = clamp(cam.y + (ty - cam.y) * k, 0, maxY)
end

function Camera.apply(cam)
  love.graphics.translate(-math.floor(cam.x), -math.floor(cam.y))
end

return Camera
