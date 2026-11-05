-- Lightweight client-only cloud wake for demo mode.
-- The aircraft leaves wisps along its recent path; the puffs stay mostly in the
-- air while the plane moves away, so the trail always forms behind it.

local Clouds = require("shared.clouds")

local CloudFx = {}
CloudFx.__index = CloudFx

function CloudFx.new()
  return setmetatable({
    inside = false,
    cloud = nil,
    emitTimer = 0,
    trailTimer = 0,
    cooldown = 0,
    trail = {},
  }, CloudFx)
end

local function addPuff(particles, x, y, vx, vy, size, life)
  particles:cloudWisp(x, y, vx, vy, size, life, { 0.91, 0.94, 0.93 })
end

function CloudFx:update(dt, plane, clouds, particles, enabled)
  for _, cloud in ipairs(clouds.list) do
    if cloud.fxPulse and cloud.fxPulse > 0 then
      cloud.fxPulse = math.max(0, cloud.fxPulse - dt * 2.2)
    end
  end

  if not enabled or not plane or not plane.alive then
    self.inside, self.cloud = false, nil
    self.emitTimer, self.trailTimer, self.cooldown = 0, 0, 0
    self.trail = {}
    return
  end

  self.cooldown = math.max(0, self.cooldown - dt)
  local cloud = Clouds.cloudAt(clouds, plane.x, plane.y)
  local inside = cloud ~= nil
  local speed = math.sqrt(plane.vx * plane.vx + plane.vy * plane.vy)
  local dir = math.atan2(plane.vy, plane.vx)
  local backX, backY = -math.cos(dir), -math.sin(dir)
  local sideX, sideY = -math.sin(dir), math.cos(dir)

  if inside then
    self.trailTimer = self.trailTimer + dt
    if self.trailTimer >= 0.025 then
      self.trailTimer = 0
      self.trail[#self.trail + 1] = {
        x = plane.x, y = plane.y, vx = plane.vx, vy = plane.vy,
      }
      if #self.trail > 24 then table.remove(self.trail, 1) end
    end
  end

  if inside and not self.inside and self.cooldown <= 0 then
    cloud.fxPulse = math.max(cloud.fxPulse or 0, 0.75)
    -- A small soft compression around the nose as the aircraft enters.
    for i = 1, 4 do
      local s = (i - 2.5) * 0.35
      addPuff(particles,
        plane.x + math.cos(dir) * 7 + sideX * s * 10,
        plane.y + math.sin(dir) * 7 + sideY * s * 10,
        sideX * (i - 2.5) * 9 - backX * 5,
        sideY * (i - 2.5) * 9 - backY * 5,
        2.5 + i * 0.8, 0.30 + i * 0.04)
    end
    self.emitTimer = 0.04
  end

  if not inside and self.inside and self.cooldown <= 0 then
    if self.cloud then self.cloud.fxPulse = math.max(self.cloud.fxPulse or 0, 1.4) end
    local points = self.trail
    if #points == 0 then
      points = { { x = plane.x, y = plane.y } }
    end
    local count = math.min(14, math.max(6, #points))
    for i = 1, count do
      local p = points[math.max(1, math.floor((i - 1) / count * #points) + 1)]
      local side = (love.math.random() - 0.5) * 2
      local along = love.math.random() * 18
      addPuff(particles,
        p.x + backX * along + sideX * side * 14,
        p.y + backY * along + sideY * side * 14,
        sideX * side * (18 + love.math.random() * 26) - (p.vx or 0) * 0.06,
        sideY * side * (18 + love.math.random() * 26) - (p.vy or 0) * 0.06,
        4.5 + love.math.random() * 7.5, 0.55 + love.math.random() * 0.55)
    end
    self.cooldown = 0.24
  end

  if inside then
    self.emitTimer = self.emitTimer - dt
    if self.emitTimer <= 0 then
      self.emitTimer = speed > 220 and 0.05 or 0.065
      local p = self.trail[math.max(1, #self.trail - 2)]
        or { x = plane.x, y = plane.y }
      local side = (love.math.random() - 0.5) * 2
      addPuff(particles,
        p.x + backX * (4 + love.math.random() * 10) + sideX * side * 8,
        p.y + backY * (4 + love.math.random() * 10) + sideY * side * 8,
        sideX * side * (8 + love.math.random() * 20) - backX * 4,
        sideY * side * (8 + love.math.random() * 20) - backY * 4,
        2.5 + love.math.random() * 4.5, 0.38 + love.math.random() * 0.38)
    end
  else
    self.emitTimer = 0
    if self.cooldown <= 0 then self.trail = {} end
  end

  self.inside = inside
  self.cloud = cloud
end

return CloudFx
