-- Pure-Lua math helpers shared by client and server.

local M = {}

M.pi = math.pi
M.tau = math.pi * 2

function M.clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

function M.wrap(v, size)
  v = v % size
  if v < 0 then v = v + size end
  return v
end

function M.wrapAngle(a)
  a = (a + math.pi) % (math.pi * 2)
  if a < 0 then a = a + math.pi * 2 end
  return a - math.pi
end

function M.angleDiff(from, to)
  return M.wrapAngle(to - from)
end

function M.angleTo(x1, y1, x2, y2)
  return math.atan2(y2 - y1, x2 - x1)
end

-- Shortest signed delta on a wrapping axis.
function M.delta(a, b, size)
  local d = (b - a) % size
  if d > size * 0.5 then d = d - size end
  return d
end

function M.dist(x1, y1, x2, y2)
  local dx, dy = x2 - x1, y2 - y1
  return math.sqrt(dx * dx + dy * dy)
end

function M.dist2(x1, y1, x2, y2)
  local dx, dy = x2 - x1, y2 - y1
  return dx * dx + dy * dy
end

-- Wrapped squared distance on both axes.
function M.wrappedDist2(x1, y1, x2, y2, w, h)
  local dx = M.delta(x1, x2, w)
  local dy = M.delta(y1, y2, h)
  return dx * dx + dy * dy
end

function M.segmentPointDist2(px, py, x1, y1, x2, y2)
  local dx, dy = x2 - x1, y2 - y1
  local l2 = dx * dx + dy * dy
  if l2 < 1e-9 then
    return (px - x1) ^ 2 + (py - y1) ^ 2
  end
  local t = M.clamp(((px - x1) * dx + (py - y1) * dy) / l2, 0, 1)
  local qx = x1 + t * dx
  local qy = y1 + t * dy
  return (px - qx) ^ 2 + (py - qy) ^ 2
end

function M.rotate(x, y, angle)
  local c, s = math.cos(angle), math.sin(angle)
  return x * c - y * s, x * s + y * c
end

return M
