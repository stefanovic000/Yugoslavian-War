-- Lightweight client-only cloud wake for demo mode.
-- Cloud collision/visibility stays server-authoritative; this only adds local
-- wisps, an entry puff, an exit scatter and a small cloud pulse.

local Clouds = require("shared.clouds")

local CloudFx = {}
CloudFx.__index = CloudFx

function CloudFx.new()
  return setmetatable({
    inside = false,
    cloud = nil,
    emitTimer = 0,
    cooldown = 0,
  }, CloudFx)
end

local function wisp(particles, x, y, vx, vy, size, life)
  particles:cloudWisp(x, y, vx, vy, size, life, { 0.90, 0.93, 0.92 })
end

function CloudFx:update(dt, plane, clouds, particles, enabled)
  for _, cloud in ipairs(clouds.list) do
    if cloud.fxPulse and cloud.fxPulse > 0 then
      cloud.fxPulse = math.max(0, cloud.fxPulse - dt * 2.2)
    end
  end

  if not enabled or not plane or not plane.alive then
    self.inside, self.cloud, self.emitTimer, self.cooldown = false, nil, 0, 0
    return
  end

  self.cooldown = math.max(0, self.cooldown - dt)
  local cloud = Clouds.cloudAt(clouds, plane.x, plane.y)
  local inside = cloud ~= nil
  local speed = math.sqrt(plane.vx * plane.vx + plane.vy * plane.vy)
  local dir = math.atan2(plane.vy, plane.vx)

  if inside and not self.inside and self.cooldown <= 0 then
    cloud.fxPulse = math.max(cloud.fxPulse or 0, 0.8)
    for i = 1, 3 do
      local a = dir + math.pi + (i - 2) * 0.5
      wisp(particles, plane.x, plane.y,
        math.cos(a) * (20 + i * 8), math.sin(a) * (20 + i * 8),
        3 + i * 1.2, 0.28 + i * 0.06)
    end
    self.emitTimer = 0.05
  end

  if not inside and self.inside and self.cooldown <= 0 then
    if self.cloud then self.cloud.fxPulse = math.max(self.cloud.fxPulse or 0, 1.5) end
    local back = dir + math.pi
    for i = 1, 10 do
      local a = back + (love.math.random() - 0.5) * 1.4
      local sp = 45 + love.math.random() * 130
      wisp(particles,
        plane.x + (love.math.random() - 0.5) * 20,
        plane.y + (love.math.random() - 0.5) * 16,
        math.cos(a) * sp - plane.vx * 0.12,
        math.sin(a) * sp - plane.vy * 0.12,
        4 + love.math.random() * 6, 0.45 + love.math.random() * 0.4)
    end
    self.cooldown = 0.25
  end

  if inside then
    self.emitTimer = self.emitTimer - dt
    if self.emitTimer <= 0 then
      self.emitTimer = 0.075
      local a = dir + math.pi + (love.math.random() - 0.5) * 1.1
      local sp = 12 + love.math.random() * 38
      wisp(particles,
        plane.x + (love.math.random() - 0.5) * 14,
        plane.y + (love.math.random() - 0.5) * 12,
        math.cos(a) * sp - plane.vx * 0.08,
        math.sin(a) * sp - plane.vy * 0.08,
        2.5 + love.math.random() * 4.5, 0.35 + love.math.random() * 0.35)
    end
  else
    self.emitTimer = 0
  end

  self.inside = inside
  self.cloud = cloud
  -- speed is only used to scale the wake; fast aircraft scatter more.
  if speed > 220 then self.emitTimer = math.min(self.emitTimer, 0.05) end
end

return CloudFx
