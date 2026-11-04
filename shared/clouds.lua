-- Deterministic clouds. Each cloud is a cluster of soft puffs. The same seed
-- on server and client produces the same cloud field, so visibility checks and
-- rendering agree without sending cloud data.

local C = require("shared.constants")
local M = require("shared.mathx")
local Rng = require("shared.rng")

local Clouds = {}

function Clouds.new(seed, count, opts)
  opts = opts or {}
  local rng = Rng.new(seed or 1)
  local list = {}
  count = count or C.CLOUDS.count

  -- One proper bank per field: several overlapping clouds that take roughly a
  -- second or two to cross at combat speed. The rest are scattered. The bank
  -- is moved as a group by avoidPoints so a spawn nudge cannot break it apart.
  local clustered = opts.cluster ~= false
  local clusterCount = clustered and math.min(4, count) or 0
  local cx = rng:range(C.WORLD.w * 0.30, C.WORLD.w * 0.70)
  local cy = rng:range(C.WORLD.h * 0.30, C.WORLD.h * 0.70)
  local clusterSpeed = rng:range(-5, 9)

  for i = 1, count do
    local x, y, r, speed, cluster
    if i <= clusterCount then
      x = M.clamp(cx + rng:range(-52, 52), 0, C.WORLD.w)
      y = M.clamp(cy + rng:range(-34, 34), 0, C.WORLD.h)
      r = rng:range(34, 46)
      speed = clusterSpeed
      cluster = 1
    else
      x = rng:range(0, C.WORLD.w)
      y = rng:range(0, C.WORLD.h)
      r = rng:range(C.CLOUDS.minRadius, C.CLOUDS.maxRadius)
      speed = rng:range(-5, 9)
      cluster = nil
    end
    local cloud = {
      x = x,
      y = y,
      r = r,
      speed = speed,
      alpha = rng:range(0.78, 0.96),
      variant = rng:int(1, 3),
      cluster = cluster,
      puffs = {},
    }
    local puffs = rng:int(5, 8)
    for j = 1, puffs do
      cloud.puffs[j] = {
        dx = rng:range(-r * 0.55, r * 0.55),
        dy = rng:range(-r * 0.24, r * 0.24),
        r = r * rng:range(0.38, 0.62),
      }
    end
    list[i] = cloud
  end

  return { list = list, w = C.WORLD.w, h = C.WORLD.h, clustered = clustered }
end

function Clouds.update(clouds, dt)
  for _, cloud in ipairs(clouds.list) do
    cloud.x = cloud.x + cloud.speed * dt
    local margin = cloud.r or 40
    if cloud.x < -margin then
      cloud.x = -margin
      cloud.speed = math.abs(cloud.speed)
    elseif cloud.x > clouds.w + margin then
      cloud.x = clouds.w + margin
      cloud.speed = -math.abs(cloud.speed)
    end
  end
end

-- True if a world point is inside a cloud puff. The arena is bounded, so no
-- wrapped copies are tested.
function Clouds.pointInside(clouds, x, y)
  for _, cloud in ipairs(clouds.list) do
    for _, puff in ipairs(cloud.puffs) do
      local dx = cloud.x + puff.dx - x
      local dy = cloud.y + puff.dy - y
      if dx * dx + dy * dy <= puff.r * puff.r then
        return true
      end
    end
  end
  return false
end

-- True if the segment a->b passes through a cloud puff.
function Clouds.segmentBlocked(clouds, x1, y1, x2, y2)
  for _, cloud in ipairs(clouds.list) do
    for _, puff in ipairs(cloud.puffs) do
      local px, py = cloud.x + puff.dx, cloud.y + puff.dy
      if M.segmentPointDist2(px, py, x1, y1, x2, y2) <= puff.r * puff.r then
        return true
      end
    end
  end
  return false
end

function Clouds.visibleBetween(clouds, x1, y1, x2, y2)
  return not Clouds.segmentBlocked(clouds, x1, y1, x2, y2)
end

-- Deterministically push cloud clusters away from spawn slots. Called by both
-- server and client so the rendered cloud field matches the collision field.
-- Cluster members share one offset, otherwise a bank can be torn apart.
function Clouds.avoidPoints(clouds, points, margin)
  margin = margin or 75
  local function puffOverlaps(cloud, point)
    for _, puff in ipairs(cloud.puffs) do
      local dx = cloud.x + puff.dx - point.x
      local dy = cloud.y + puff.dy - point.y
      local rr = puff.r + margin
      if dx * dx + dy * dy < rr * rr then return true end
    end
    return false
  end

  for _ = 1, 2 do
    local offsets = {}
    for _, cloud in ipairs(clouds.list) do
      local key = cloud.cluster or ("single:" .. tostring(cloud))
      if not offsets[key] then
        for _, point in ipairs(points) do
          if puffOverlaps(cloud, point) then
            offsets[key] = { x = 230, y = 117 }
            break
          end
        end
      end
    end
    for _, cloud in ipairs(clouds.list) do
      local key = cloud.cluster or ("single:" .. tostring(cloud))
      local off = offsets[key]
      if off then
        cloud.x = M.clamp(cloud.x + off.x, -cloud.r, clouds.w + cloud.r)
        cloud.y = M.clamp(cloud.y + off.y, 0, clouds.h)
      end
    end
  end

  -- A huge cluster can still land on a spawn after the two group nudges.
  -- Drop only those puffs/clouds rather than allow a spawn to be cloud-hidden.
  for i = #clouds.list, 1, -1 do
    local cloud = clouds.list[i]
    local hit = false
    for _, point in ipairs(points) do
      if puffOverlaps(cloud, point) then hit = true; break end
    end
    if hit then table.remove(clouds.list, i) end
  end
end

return Clouds
