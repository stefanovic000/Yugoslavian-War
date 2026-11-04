-- Data-driven side-view aircraft art.
--
-- A plane definition selects an art id. Each art entry is a small part kit
-- (fuselage, wing, tail, canopy, markings) instead of a branch in gameplay
-- code. New aircraft can therefore share rendering, damage and team logic.

local ARTS = {
  ik3 = {
    scale = 0.95,
    body = { 18, 0, 14, -4, 5, -5, -6, -4, -15, -2, -15, 2, -6, 4, 5, 5, 14, 4 },
    nose = { 18, 0, 14, -3, 14, 3 },
    wing = { 8, 1, 5, 5, -8, 5, -10, 1, -2, 0 },
    wingBroken = { 6, 1, 3, 4, -4, 4, -5, 1 },
    tailplane = { -11, 0, -19, 3, -10, 2 },
    fin = { -12, -1, -20, -10, -11, -3 },
    canopy = { 6, -4, 3, -7, -1, -6, -2, -3 },
    radiator = { -2, 4, 4, 4, 2, 7, -3, 6 },
    guns = { 12, -1, 18, -1, 18, 1, 12, 1 },
    roundel = { x = -5, y = 0, r = 3.2, kind = "yugoslav" },
    tailBand = { x = -19, y = -8, w = 6, h = 1.2 },
  },

  bf109e = {
    scale = 0.96,
    body = { 19, 0, 15, -3, 6, -4, -5, -4, -15, -2, -15, 2, -5, 4, 6, 4, 15, 3 },
    nose = { 19, 0, 15, -3, 15, 3 },
    wing = { 10, 1, 6, 5, -7, 5, -9, 1, -2, 0 },
    wingBroken = { 7, 1, 4, 4, -4, 4, -5, 1 },
    tailplane = { -10, 0, -18, 2, -10, 2 },
    fin = { -11, -1, -18, -9, -10, -3 },
    canopy = { 5, -4, 2, -6, -1, -5, -2, -3 },
    radiator = { -1, 4, 5, 4, 3, 7, -2, 6 },
    guns = { 13, -1, 19, -1, 19, 1, 13, 1 },
    roundel = { x = -6, y = 0, r = 3.0, kind = "balkan" },
    tailBand = { x = -18, y = -7, w = 6, h = 1.2 },
    noseAccent = true,
  },
}

local INK = { 0.055, 0.070, 0.090 }

local PlaneArt = {}

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

local function drawRoundel(kind, x, y, r, alpha)
  if kind == "balkan" then
    setColor({ 0.94, 0.92, 0.84 }, 0.9 * alpha)
    love.graphics.rectangle("fill", x - r, y - 0.7, r * 1.8, 1.4)
    love.graphics.rectangle("fill", x - 0.7, y - r, 1.4, r * 1.8)
    setColor(INK, 0.95 * alpha)
    love.graphics.rectangle("fill", x - r * 0.55, y - 0.35, r * 1.1, 0.7)
    love.graphics.rectangle("fill", x - 0.35, y - r * 0.55, 0.7, r * 1.1)
  else
    setColor({ 0.66, 0.15, 0.13 }, 0.95 * alpha)
    love.graphics.circle("fill", x, y, r)
    setColor({ 0.92, 0.90, 0.80 }, 0.95 * alpha)
    love.graphics.circle("fill", x, y, r * 0.64)
    setColor({ 0.14, 0.24, 0.50 }, 0.95 * alpha)
    love.graphics.circle("fill", x, y, r * 0.30)
    setColor({ 0.95, 0.93, 0.84 }, 0.9 * alpha)
    love.graphics.rectangle("fill", x - r * 0.45, y - 0.4, r * 0.9, 0.8)
    love.graphics.rectangle("fill", x - 0.4, y - r * 0.45, 0.8, r * 0.9)
  end
end

local function drawTailFlash(band, alpha)
  if not band then return end
  local colors = {
    { 0.16, 0.28, 0.55 },
    { 0.90, 0.88, 0.78 },
    { 0.62, 0.16, 0.14 },
  }
  for i = 1, 3 do
    setColor(colors[i], 0.9 * alpha)
    love.graphics.rectangle("fill", band.x, band.y + (i - 1) * band.h, band.w, band.h)
  end
end

local function drawBody(plane, art, colors, alpha)
  local tailHp = plane.parts and plane.parts.tail or 60
  local wingHp = plane.parts and plane.parts.wing or 60
  local engineHp = plane.parts and plane.parts.engine or 60
  local gunsHp = plane.parts and plane.parts.guns or 60

  if tailHp > 22 then
    poly(art.fin, colors.dark, alpha)
    outline(art.fin, INK, 0.8 * alpha)
    drawTailFlash(art.tailBand, alpha)
  end

  poly(art.tailplane, colors.dark, alpha)

  poly(art.body, colors.body, alpha)
  outline(art.body, INK, 0.9 * alpha)
  poly(art.nose, art.noseAccent and colors.accent or colors.dark, alpha)

  if wingHp > 22 then
    poly(art.wing, colors.dark, alpha)
    outline(art.wing, INK, 0.8 * alpha)
    poly({ 5, 1, -2, 3, -9, 3, -8, 1 }, colors.body, 0.75 * alpha)
  else
    poly(art.wingBroken, colors.dark, alpha)
  end

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

  poly(art.radiator, colors.dark, alpha)
  outline(art.radiator, INK, 0.45 * alpha)

  poly(art.canopy, colors.light, alpha)
  outline(art.canopy, INK, 0.7 * alpha)
  setColor(INK, 0.5 * alpha)
  love.graphics.line(-1, -6, 0, -4)

  local roundel = art.roundel
  drawRoundel(roundel.kind, roundel.x, roundel.y, roundel.r, alpha)

  if gunsHp > 18 then
    poly(art.guns, INK, 0.85 * alpha)
  end

  if plane.alive then
    local power = 0.4 + (plane.throttle or 0.5) * 0.8
    setColor(INK, 0.18 * alpha)
    love.graphics.ellipse("fill", 18.5, 0, 1.2, 7 * power)
    setColor(colors.accent, 0.9 * alpha)
    love.graphics.circle("fill", 18, 0, 1.4)
  end

  if plane.hitFlash and plane.hitFlash > 0 then
    setColor({ 1, 1, 1 }, 0.45 * alpha)
    love.graphics.polygon("fill", art.body)
  end
end

function PlaneArt.draw(plane, time, opts)
  opts = opts or {}
  local visual = plane.spec and plane.spec.visual
  local art = ARTS[visual and visual.art or "ik3"] or ARTS.ik3
  local colors = opts.colors or (visual and visual.palette) or {
    body = { 0.36, 0.42, 0.25 },
    dark = { 0.17, 0.22, 0.13 },
    light = { 0.66, 0.72, 0.50 },
    accent = { 0.82, 0.70, 0.32 },
  }
  local alpha = opts.alpha or 1
  if plane.invuln and plane.invuln > 0 and math.floor(time * 18) % 2 == 0 then
    alpha = alpha * 0.45
  end
  local scale = (visual and visual.scale) or art.scale or 0.95
  local c = math.cos(plane.angle)
  local blend = math.min(1, math.abs(c) / 0.18)

  local function drawAt(mirror, a)
    love.graphics.push()
    love.graphics.translate(plane.x, plane.y)
    if mirror then
      love.graphics.rotate(plane.angle - math.pi)
      love.graphics.scale(-1, 1)
    else
      love.graphics.rotate(plane.angle)
    end
    love.graphics.scale(scale, scale)
    drawBody(plane, art, colors, a)
    love.graphics.pop()
  end

  if blend >= 0.999 then
    drawAt(c < 0, alpha)
  else
    local mirrorMain = c < 0
    drawAt(mirrorMain, alpha * (0.5 + 0.5 * blend))
    drawAt(not mirrorMain, alpha * (0.5 - 0.5 * blend))
  end
end

return PlaneArt

