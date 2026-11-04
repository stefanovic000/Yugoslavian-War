-- Code-drawn pixel-art sprites. No external image assets, so startup stays
-- fast and every plane/cloud scales crisply in the 640x360 canvas.

local Shapes = require("shared.cloud_shapes")
local PlaneArt = require("src.game.planeart")

local Sprites = {}

local TEAM = {
  player = {
    body = { 0.36, 0.42, 0.25 },
    dark = { 0.17, 0.22, 0.13 },
    light = { 0.66, 0.72, 0.50 },
    accent = { 0.82, 0.70, 0.32 },
  },
  enemy = {
    body = { 0.60, 0.48, 0.30 },
    dark = { 0.28, 0.22, 0.14 },
    light = { 0.84, 0.75, 0.55 },
    accent = { 0.62, 0.18, 0.15 },
  },
}

Sprites.TEAM = TEAM

-- Draw one plane at its current position. Aircraft art is data-driven in
-- PlaneArt; this module owns team colours and the cloud/bullet sprite helpers.
function Sprites.drawPlane(plane, time, opts)
  opts = opts or {}
  local visual = plane.spec and plane.spec.visual
  local colors = opts.colors or (visual and visual.palette) or TEAM[plane.team == 1 and "player" or "enemy"]
  PlaneArt.draw(plane, time, { colors = colors, alpha = opts.alpha })
end

-- Draw all wrapping copies of a plane. World is toroidal, so a plane at x=2
-- also appears at x=642 (right edge) for the camera.
function Sprites.drawPlaneCopies(plane, time, opts)
  Sprites.drawPlane(plane, time, opts)
end

function Sprites.drawBullet(bullet)
  local color = bullet.team == 1 and { 0.55, 0.95, 0.95 } or { 1.0, 0.68, 0.32 }
  local len = 7
  local speed = math.sqrt(bullet.vx * bullet.vx + bullet.vy * bullet.vy)
  if speed < 0.01 then return end
  local dx, dy = bullet.vx / speed * len, bullet.vy / speed * len

  love.graphics.setColor(color[1], color[2], color[3], 0.35)
  love.graphics.setLineWidth(2)
  love.graphics.line(bullet.x, bullet.y, bullet.x - dx, bullet.y - dy)
  love.graphics.setColor(1, 1, 1, 0.95)
  love.graphics.rectangle("fill", bullet.x - 1, bullet.y - 1, 2, 2)
end

function Sprites.drawPickup(pickup, time)
  local bob = math.sin(time * 2.4 + (pickup.phase or 0)) * 2
  local x, y = pickup.x, pickup.y + bob

  -- parachute
  love.graphics.setColor(0.96, 0.92, 0.78, 0.95)
  love.graphics.circle("fill", x, y - 15, 10, 12)
  love.graphics.setColor(0.86, 0.44, 0.24, 0.95)
  love.graphics.circle("fill", x, y - 15, 6, 12)
  love.graphics.setColor(0.20, 0.24, 0.26, 0.9)
  love.graphics.setLineWidth(1)
  love.graphics.line(x - 8, y - 10, x - 4, y - 3)
  love.graphics.line(x + 8, y - 10, x + 4, y - 3)
  love.graphics.line(x, y - 22, x, y - 3)

  -- crate
  love.graphics.setColor(0.55, 0.36, 0.18, 1)
  love.graphics.rectangle("fill", x - 5, y - 3, 10, 9)
  love.graphics.setColor(0.92, 0.72, 0.30, 1)
  love.graphics.rectangle("fill", x - 5, y - 3, 10, 2)
  love.graphics.setColor(0.10, 0.12, 0.10, 0.8)
  love.graphics.rectangle("line", x - 5.5, y - 3.5, 11, 10)
end

-- One cloud, optionally offset for wrapping. alphaMul lets the caller fade.
local cloudImages = nil
local glowImage = nil

local BAYER = {
  { 0, 8, 2, 10 },
  { 12, 4, 14, 6 },
  { 3, 11, 1, 9 },
  { 15, 7, 13, 5 },
}

local CLOUD_LEVELS = {
  { 0.47, 0.58, 0.61 },
  { 0.68, 0.77, 0.77 },
  { 0.83, 0.87, 0.83 },
  { 0.94, 0.93, 0.83 },
}

local function makeCloudImage(variant)
  local w, h = 96, 56
  local data = love.image.newImageData(w, h)
  local blobs = Shapes.blobs(variant)
  data:mapPixel(function(px, py)
    local x, y = px + 0.5, py + 0.5
    local mask = 0
    for _, b in ipairs(blobs) do
      local dx = (x - b[1]) / b[3]
      local dy = (y - b[2]) / b[4]
      local d = dx * dx + dy * dy
      if d < 1 then
        local v = 1 - d
        v = v * v * (3 - 2 * v)
        if v > mask then mask = v end
      end
    end
    if y > 42 then
      mask = mask * math.max(0, (56 - y) / 12)
    end

    local v = mask * 3.4
    local base = math.floor(v)
    local frac = v - base
    local threshold = (BAYER[(py % 4) + 1][(px % 4) + 1] + 0.5) / 16
    local level = base + ((frac > threshold) and 1 or 0)
    level = math.max(0, math.min(3, level))
    if level == 0 then
      return 0, 0, 0, 0
    end
    local c = CLOUD_LEVELS[level]
    return c[1], c[2], c[3], 1
  end)
  local image = love.graphics.newImage(data)
  image:setFilter("nearest", "nearest")
  return image
end

function Sprites.init()
  if not cloudImages then
    cloudImages = { makeCloudImage(1), makeCloudImage(2), makeCloudImage(3) }
  end
  if not glowImage then
    local size = 64
    local data = love.image.newImageData(size, size)
    local half = (size - 1) * 0.5
    data:mapPixel(function(px, py)
      local dx, dy = (px - half) / half, (py - half) / half
      local d = math.sqrt(dx * dx + dy * dy)
      local a = math.max(0, 1 - d)
      a = a * a
      return 1, 1, 1, a
    end)
    glowImage = love.graphics.newImage(data)
    glowImage:setFilter("nearest", "nearest")
  end
end

function Sprites.drawGlow(x, y, radius, color, alpha)
  Sprites.init()
  love.graphics.push("all")
  love.graphics.setBlendMode("add")
  love.graphics.setColor(color[1], color[2], color[3], alpha)
  local s = radius * 2 / 64
  love.graphics.draw(glowImage, x, y, 0, s, s, 32, 32)
  love.graphics.pop()
end

function Sprites.drawCloud(cloud, ox, oy, alphaMul)
  Sprites.init()
  local a = (cloud.alpha or 0.9) * (alphaMul or 1)
  local image = cloudImages[cloud.variant or 1]
  local x, y = cloud.x + ox, cloud.y + oy
  local sx = cloud.r * 2.0 / 96
  local sy = cloud.r * 1.3 / 56

  love.graphics.setColor(0.04, 0.08, 0.09, a * 0.35)
  love.graphics.draw(image, x + 3, y + 4, 0, sx, sy, 48, 28)
  love.graphics.setColor(1, 1, 1, a)
  love.graphics.draw(image, x, y, 0, sx, sy, 48, 28)
end

function Sprites.drawCloudCopies(cloud, alphaMul)
  -- The walled arena is bounded: drawing wrapped copies made a cloud appear
  -- behind the player while the vision raycast used a different real position.
  Sprites.drawCloud(cloud, 0, 0, alphaMul)
end

return Sprites

