-- Deterministic clouds. Each cloud is a cluster of soft puffs. The same seed
-- on server and client produces the same cloud field, so visibility checks and
-- rendering agree without sending cloud data.

local C = require("shared.constants")
local M = require("shared.mathx")
local Rng = require("shared.rng")
local Shapes = require("shared.cloud_shapes")

local Clouds = {}

function Clouds.new(seed, count, opts)
  opts = opts or {}
  local rng = Rng.new(seed or 1)
  local list = {}
  count = count or C.CLOUDS.count

  -- One proper bank per field: several overlapping clouds that take roughly a
  -- second or two to cross at combat speed. The rest are scattered. The bank
  -- is moved as a group by avoidPoints so a spawn nudge cannot break it apart.
  -- Demo fields use several wider, shallower banks spread across the arena.
  local clustered = opts.cluster ~= false
  local horizontal = clustered and count >= C.CLOUDS.demoCount
  local bankCount = horizontal and 6 or 1
  local clusterCount = clustered and (horizontal and count or math.min(4, count)) or 0
  local perBank = horizontal and math.max(3, math.ceil(count / bankCount)) or 4

  local banks = {}
  for g = 1, bankCount do
    local cx
    if horizontal then
      cx = C.WORLD.w * (g / (bankCount + 1)) + rng:range(-30, 30)
    else
      cx = rng:range(C.WORLD.w * 0.30, C.WORLD.w * 0.70)
    end
    banks[g] = {
      x = cx,
      y = rng:range(C.WORLD.h * 0.30,
        C.WORLD.h * (horizontal and 0.64 or 0.70)),
      speed = rng:range(-5, 9),
    }
  end

  for i = 1, count do
    local x, y, r, speed, cluster
    if i <= clusterCount then
      local group = horizontal and (math.floor((i - 1) / perBank) + 1) or 1
      if group > bankCount then group = bankCount end
      local bank = banks[group]
      local spreadX = horizontal and 72 or 52
      local spreadY = horizontal and 18 or 34
      x = M.clamp(bank.x + rng:range(-spreadX, spreadX), 0, C.WORLD.w)
      y = M.clamp(bank.y + rng:range(-spreadY, spreadY), 0, C.WORLD.h)
      r = rng:range(horizontal and 30 or 34, horizontal and 42 or 46)
      speed = bank.speed
      cluster = group
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
    cloud.puffs = Shapes.puffs(cloud.variant, r)
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
      local rx = puff.rx or puff.r
      local ry = puff.ry or puff.r
      if (dx * dx) / (rx * rx) + (dy * dy) / (ry * ry) <= 1 then
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
      local cx = cloud.x + puff.dx
      local cy = cloud.y + puff.dy
      local rx = puff.rx or puff.r
      local ry = puff.ry or puff.r
      local nx1, ny1 = (x1 - cx) / rx, (y1 - cy) / ry
      local nx2, ny2 = (x2 - cx) / rx, (y2 - cy) / ry
      if M.segmentPointDist2(0, 0, nx1, ny1, nx2, ny2) <= 1 then
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
      local rx = (puff.rx or puff.r) + margin
      local ry = (puff.ry or puff.r) + margin
      if (dx * dx) / (rx * rx) + (dy * dy) / (ry * ry) < 1 then return true end
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
