-- Code-drawn pixel-art sprites. No external image assets, so startup stays
-- fast and every plane/cloud scales crisply in the 640x360 canvas.

local C = require("shared.constants")
local M = require("shared.mathx")

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

local INK = { 0.055, 0.070, 0.090 }

local function setColor(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or 1)
end

local function poly(points, color, a)
  setColor(color, a)
  love.graphics.polygon("fill", points)
end

local function outline(points, color, a)
  setColor(color, a)
  love.graphics.setLineWidth(1)
  love.graphics.polygon("line", points)
end

-- Draw one plane at its current position (no wrap copies).
function Sprites.drawPlane(plane, time, opts)
  opts = opts or {}
  local colors = TEAM[plane.team == 1 and "player" or "enemy"] or TEAM.enemy
  if opts.colors then colors = opts.colors end

  local alpha = opts.alpha or 1
  if plane.invuln and plane.invuln > 0 and math.floor(time * 18) % 2 == 0 then
    alpha = alpha * 0.45
  end

  local wingHp = plane.parts and plane.parts.wing or 60
  local tailHp = plane.parts and plane.parts.tail or 60
  local engineHp = plane.parts and plane.parts.engine or 60
  local gunsHp = plane.parts and plane.parts.guns or 60

  local function drawBody(alpha)

  -- vertical fin / rudder
  if tailHp > 22 then
    local fin = { -12, -1, -20, -10, -11, -3 }
    poly(fin, colors.dark, alpha)
    outline(fin, INK, 0.8 * alpha)

    -- Yugoslav tail flash: blue / white / red bands.
    setColor({ 0.16, 0.28, 0.55 }, 0.9 * alpha)
    love.graphics.rectangle("fill", -18.5, -7.5, 4.5, 1.2)
    setColor({ 0.90, 0.88, 0.78 }, 0.9 * alpha)
    love.graphics.rectangle("fill", -18.5, -6.3, 4.5, 1.2)
    setColor({ 0.62, 0.16, 0.14 }, 0.9 * alpha)
    love.graphics.rectangle("fill", -18.5, -5.1, 4.5, 1.2)
  end

  -- horizontal stabilizer
  poly({ -11, 0, -19, 4, -10, 2 }, colors.dark, alpha)

  -- low wing: single monoplane wing, broad and slightly tapered
  if wingHp > 22 then
    local wing = { 8, 2, 3, 11, -11, 11, -14, 4, -4, 3 }
    poly(wing, colors.dark, alpha)
    outline(wing, INK, 0.8 * alpha)
    -- wing root fairing
    poly({ 5, 2, -2, 6, -9, 6, -8, 3 }, colors.body, 0.8 * alpha)
    if wingHp < 45 then
      setColor(INK, 0.55 * alpha)
      love.graphics.rectangle("fill", -7, 6, 3, 3)
    end
  else
    poly({ 5, 2, -2, 4, -8, 4, -7, 2 }, colors.dark, alpha)
  end

  -- radial/inline engine cowling
  local body = { 18, 0, 14, -4, 5, -5, -6, -4, -15, -2, -15, 2, -6, 4, 5, 5, 14, 4 }
  poly(body, colors.body, alpha)
  outline(body, INK, 0.9 * alpha)

  -- nose cowling and exhaust stacks
  poly({ 18, 0, 14, -3, 14, 3 }, colors.dark, alpha)
  if engineHp <= 22 then
    setColor(INK, 0.85 * alpha)
    love.graphics.rectangle("fill", 14, -3, 4, 6)
    setColor({ 0.95, 0.45, 0.22 }, 0.8 * alpha)
    love.graphics.rectangle("fill", 15, -1, 2, 2)
  end
  setColor(INK, 0.7 * alpha)
  love.graphics.rectangle("fill", 12, -3, 1, 5)
  love.graphics.rectangle("fill", 9, -3, 1, 5)
  love.graphics.rectangle("fill", 6, -3, 1, 4)

  -- radiator bath under the fuselage
  poly({ -2, 4, 4, 4, 2, 7, -3, 6 }, colors.dark, alpha)
  outline({ -2, 4, 4, 4, 2, 7, -3, 6 }, INK, 0.45 * alpha)

  -- framed cockpit canopy
  local canopy = { 6, -4, 3, -7, -1, -6, -2, -3 }
  poly(canopy, colors.light, alpha)
  outline(canopy, INK, 0.7 * alpha)
  setColor(INK, 0.5 * alpha)
  love.graphics.line(-1, -6, 0, -4)

  -- Yugoslavia: red / white / blue roundel with the white cross.
  if plane.team == 1 then
    setColor({ 0.66, 0.15, 0.13 }, 0.95 * alpha)
    love.graphics.circle("fill", -5, 0, 3.2)
    setColor({ 0.92, 0.90, 0.80 }, 0.95 * alpha)
    love.graphics.circle("fill", -5, 0, 2.1)
    setColor({ 0.14, 0.24, 0.50 }, 0.95 * alpha)
    love.graphics.circle("fill", -5, 0, 1.0)
    setColor({ 0.95, 0.93, 0.84 }, 0.9 * alpha)
    love.graphics.rectangle("fill", -6.4, -0.4, 2.8, 0.8)
    love.graphics.rectangle("fill", -5.4, -1.4, 0.8, 2.8)
  else
    -- enemy Balkan cross
    setColor({ 0.94, 0.92, 0.84 }, 0.9 * alpha)
    love.graphics.rectangle("fill", -6.6, -2.2, 3.2, 1.0)
    love.graphics.rectangle("fill", -5.5, -3.1, 1.0, 3.2)
    setColor(INK, 0.95 * alpha)
    love.graphics.rectangle("fill", -6.1, -1.8, 2.2, 0.5)
    love.graphics.rectangle("fill", -5.25, -2.7, 0.5, 2.2)
  end

  -- gun barrels in the wing
  if gunsHp > 18 then
    setColor(INK, 0.85 * alpha)
    love.graphics.rectangle("fill", 12, -1, 6, 1)
    love.graphics.rectangle("fill", 12, 1, 6, 1)
  end

  -- propeller disc and spinner
  if plane.alive then
    local power = 0.4 + (plane.throttle or 0.5) * 0.8
    setColor(INK, 0.18 * alpha)
    love.graphics.ellipse("fill", 18.5, 0, 1.2, 7 * power)
    setColor(colors.accent, 0.9 * alpha)
    love.graphics.circle("fill", 18, 0, 1.4)
  end

  if plane.hitFlash and plane.hitFlash > 0 then
    setColor({ 1, 1, 1 }, 0.45 * alpha)
    love.graphics.polygon("fill", body)
  end
  end -- drawBody

  local c = math.cos(plane.angle)
  local blend = math.min(1, math.abs(c) / 0.18)

  local function drawAt(mirror, a)
    love.graphics.push()
    love.graphics.translate(plane.x, plane.y)
    if mirror then
      -- LÖVE applies this as rotate-then-mirror. Mirroring the local art first
      -- keeps the nose on plane.angle; the old reverse order flipped the nose
      -- vertically at diagonal left-facing poses.
      love.graphics.rotate(plane.angle - math.pi)
      love.graphics.scale(-1, 1)
    else
      love.graphics.rotate(plane.angle)
    end
    drawBody(a)
    love.graphics.pop()
  end

  if blend >= 0.999 then
    drawAt(c < 0, alpha)
  else
    -- Crossfade between the upright left and right poses near the vertical.
    -- The silhouette is the same plane; only the asymmetric cockpit/fin detail
    -- swaps sides, so this avoids the hard "flip" when looking straight up.
    local mirrorMain = c < 0
    drawAt(mirrorMain, alpha * (0.5 + 0.5 * blend))
    drawAt(not mirrorMain, alpha * (0.5 - 0.5 * blend))
  end
end

-- Draw all wrapping copies of a plane. World is toroidal, so a plane at x=2
-- also appears at x=642 (right edge) for the camera.
function Sprites.drawPlaneCopies(plane, time, opts)
  local w = C.WORLD.w
  for _, ox in ipairs({ 0, -w, w }) do
    local x = plane.x + ox
    local y = plane.y
    if x > -30 and x < w + 30 and y > -30 and y < C.WORLD.h + 30 then
      local copy = plane
      if ox ~= 0 then
        copy = setmetatable({ x = x, y = y }, { __index = plane })
      end
      Sprites.drawPlane(copy, time, opts)
    end
  end
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
  local sets = {
    { { 30, 34, 18, 12 }, { 48, 28, 24, 16 }, { 66, 34, 16, 11 }, { 39, 23, 14, 10 } },
    { { 28, 32, 16, 11 }, { 45, 28, 22, 15 }, { 63, 33, 18, 12 }, { 78, 38, 9, 7 } },
    { { 34, 30, 20, 13 }, { 54, 32, 22, 14 }, { 70, 34, 13, 9 }, { 22, 38, 9, 7 } },
  }
  local blobs = sets[variant] or sets[1]
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
  local w, h = C.WORLD.w, C.WORLD.h
  for _, ox in ipairs({ 0, -w, w }) do
    for _, oy in ipairs({ 0, -h, h }) do
      if cloud.x + ox > -90 and cloud.x + ox < w + 90
        and cloud.y + oy > -90 and cloud.y + oy < h + 90 then
        Sprites.drawCloud(cloud, ox, oy, alphaMul)
      end
    end
  end
end

return Sprites
