-- Small pooled particle system for muzzle flashes, hits, smoke and explosions.

local Particles = {}
Particles.__index = Particles

local function nowColor(r, g, b, a)
  return { r, g, b, a or 1 }
end

function Particles.new(max)
  return setmetatable({
    max = max or 700,
    items = {},
    pool = {},
  }, Particles)
end

function Particles:acquire()
  return table.remove(self.pool) or {}
end

function Particles:add(p)
  if #self.items >= self.max then return end
  self.items[#self.items + 1] = p
end

function Particles:smoke(x, y, vx, vy, size, life, color)
  local p = self:acquire()
  p.kind = "smoke"
  p.x, p.y, p.vx, p.vy = x, y, vx, vy
  p.size, p.life, p.maxLife = size, life, life
  p.color = color or nowColor(0.62, 0.64, 0.64)
  p.grow = size * 1.2
  p.drag = 1.2
  self:add(p)
end

function Particles:spark(x, y, angle, speed, life, color)
  local p = self:acquire()
  p.kind = "spark"
  p.x, p.y = x, y
  p.vx, p.vy = math.cos(angle) * speed, math.sin(angle) * speed
  p.life, p.maxLife = life, life
  p.color = color or nowColor(1, 0.72, 0.25)
  p.size = 2
  p.grow = 0
  p.drag = 2
  self:add(p)
end

function Particles:flash(x, y, size, life, color)
  local p = self:acquire()
  p.kind = "flash"
  p.x, p.y = x, y
  p.vx, p.vy = 0, 0
  p.size, p.life, p.maxLife = size, life, life
  p.color = color or nowColor(1, 0.9, 0.55)
  p.grow = size * 2.5
  p.drag = 0
  self:add(p)
end

function Particles:ring(x, y, size, life, color)
  local p = self:acquire()
  p.kind = "ring"
  p.x, p.y = x, y
  p.vx, p.vy = 0, 0
  p.size, p.life, p.maxLife = size, life, life
  p.color = color or nowColor(1, 0.8, 0.4)
  p.grow = size * 4
  p.drag = 0
  self:add(p)
end

function Particles:muzzle(x, y, angle, color)
  self:flash(x, y, 4, 0.07, color or nowColor(1, 0.9, 0.55))
  for _ = 1, 2 do
    local a = angle + (love.math.random() - 0.5) * 0.5
    self:spark(x, y, a, 90 + love.math.random() * 80, 0.10, color)
  end
end

function Particles:hit(x, y, angle, color)
  for _ = 1, 4 do
    local a = angle + math.pi + (love.math.random() - 0.5) * 1.8
    self:spark(x, y, a, 60 + love.math.random() * 130, 0.18 + love.math.random() * 0.15, color)
  end
  self:flash(x, y, 4, 0.06, color)
end

function Particles:explosion(x, y, color, scale)
  scale = scale or 1
  self:flash(x, y, 10 * scale, 0.18, nowColor(1, 0.85, 0.45))
  self:ring(x, y, 6 * scale, 0.35, color or nowColor(1, 0.55, 0.25))
  for _ = 1, math.floor(18 * scale) do
    local a = love.math.random() * math.pi * 2
    self:spark(x, y, a, 70 + love.math.random() * 210, 0.25 + love.math.random() * 0.45, color)
  end
  for _ = 1, math.floor(6 * scale) do
    self:smoke(x, y, (love.math.random() - 0.5) * 50, (love.math.random() - 0.5) * 50,
      4 + love.math.random() * 6, 0.6 + love.math.random() * 0.6, nowColor(0.38, 0.38, 0.38))
  end
end

function Particles:engineTrail(x, y, vx, vy, strength)
  self:smoke(x, y, vx, vy, 2 + strength * 3, 0.35 + strength * 0.4,
    nowColor(0.55, 0.58, 0.58))
end

function Particles:cloudWisp(x, y, vx, vy, size, life, color)
  local p = self:acquire()
  p.kind = "cloud"
  p.x, p.y, p.vx, p.vy = x, y, vx, vy
  p.size, p.life, p.maxLife = size, life, life
  p.color = color or nowColor(0.90, 0.93, 0.92)
  p.grow = size * 0.9
  p.drag = 1.8
  p.rot = love.math.random() * math.pi * 2
  p.spin = (love.math.random() - 0.5) * 1.8
  p.curl = (love.math.random() - 0.5) * 2.4
  self:add(p)
end

function Particles:update(dt)
  local items = self.items
  local i = 1
  while i <= #items do
    local p = items[i]
    p.life = p.life - dt
    if p.life <= 0 then
      items[i] = items[#items]
      items[#items] = nil
      self.pool[#self.pool + 1] = p
    else
      if p.drag and p.drag > 0 then
        local k = math.max(0, 1 - p.drag * dt)
        p.vx, p.vy = p.vx * k, p.vy * k
      end
      if p.kind == "cloud" and p.curl then
        local c, s = math.cos(p.curl * dt), math.sin(p.curl * dt)
        p.vx, p.vy = p.vx * c - p.vy * s, p.vx * s + p.vy * c
        p.rot = (p.rot or 0) + (p.spin or 0) * dt
      end
      p.x = p.x + p.vx * dt
      p.y = p.y + p.vy * dt
      p.size = p.size + (p.grow or 0) * dt
      i = i + 1
    end
  end
end

function Particles:draw()
  love.graphics.push("all")
  for _, p in ipairs(self.items) do
    local t = p.life / p.maxLife
    if p.kind == "smoke" then
      love.graphics.setColor(p.color[1], p.color[2], p.color[3], 0.42 * t)
      love.graphics.circle("fill", p.x, p.y, p.size, 8)
    elseif p.kind == "spark" then
      love.graphics.setColor(p.color[1], p.color[2], p.color[3], t)
      love.graphics.setLineWidth(1)
      love.graphics.line(p.x, p.y, p.x - p.vx * 0.02, p.y - p.vy * 0.02)
    elseif p.kind == "flash" then
      love.graphics.setColor(p.color[1], p.color[2], p.color[3], 0.75 * t)
      love.graphics.circle("fill", p.x, p.y, p.size, 10)
    elseif p.kind == "ring" then
      love.graphics.setColor(p.color[1], p.color[2], p.color[3], 0.8 * t)
      love.graphics.setLineWidth(1)
      love.graphics.circle("line", p.x, p.y, p.size, 16)
    elseif p.kind == "cloud" then
      -- Cloud wisps are drawn after the cloud layer so they read on top.
    end
  end
  love.graphics.pop()
end

function Particles:cloudImage()
  if self._cloudImage then return self._cloudImage end
  local size = 64
  local data = love.image.newImageData(size, size)
  local half = (size - 1) * 0.5
  data:mapPixel(function(px, py)
    local dx, dy = (px - half) / half, (py - half) / half
    local d = math.sqrt(dx * dx + dy * dy)
    local a = math.max(0, 1 - d)
    a = a * a * (3 - 2 * a)
    return 1, 1, 1, a
  end)
  self._cloudImage = love.graphics.newImage(data)
  self._cloudImage:setFilter("linear", "linear")
  return self._cloudImage
end

function Particles:drawCloud()
  local img = self:cloudImage()
  love.graphics.push("all")
  love.graphics.setBlendMode("alpha")
  for _, p in ipairs(self.items) do
    if p.kind == "cloud" then
      local t = p.life / p.maxLife
      local scale = p.size / 26
      love.graphics.setColor(p.color[1], p.color[2], p.color[3], 0.30 * t)
      love.graphics.draw(img, p.x, p.y, p.rot or 0, scale * 1.35, scale * 0.95, 32, 32)
      love.graphics.setColor(1, 1, 1, 0.16 * t)
      love.graphics.draw(img, p.x - p.size * 0.12, p.y - p.size * 0.10,
        p.rot or 0, scale * 0.62, scale * 0.48, 32, 32)
    end
  end
  love.graphics.pop()
end

function Particles:count()
  return #self.items
end

return Particles
