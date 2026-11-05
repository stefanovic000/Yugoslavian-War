-- Demo-only cloud wake ribbon. A short turbulent strip is laid along the
-- aircraft's recent path and fades in the air after it leaves the cloud.

local CloudWake = {}
CloudWake.__index = CloudWake

local TEXTURE = nil
local MAX_POINTS = 56
local LIFETIME = 0.85

local function texture()
  if TEXTURE then return TEXTURE end
  local w, h = 64, 1
  local data = love.image.newImageData(w, h)
  data:mapPixel(function(px)
    local t = (px + 0.5) / w
    local a = math.max(0, 1 - math.abs(t * 2 - 1))
    a = a * a * (3 - 2 * a)
    return 1, 1, 1, a
  end)
  TEXTURE = love.graphics.newImage(data)
  TEXTURE:setFilter("linear", "linear")
  TEXTURE:setWrap("clamp", "clamp")
  return TEXTURE
end

function CloudWake.new()
  return setmetatable({
    points = {},
    emit = 0,
    time = 0,
  }, CloudWake)
end

function CloudWake:clear()
  self.points = {}
  self.emit = 0
end

function CloudWake:update(dt, plane, inside, speed, dir)
  self.time = self.time + dt
  self.emit = self.emit - dt
  for i = #self.points, 1, -1 do
    local p = self.points[i]
    p.age = p.age + dt
    if p.age >= LIFETIME then table.remove(self.points, i) end
  end
  if not inside or not plane then return end

  if self.emit <= 0 then
    self.emit = speed > 220 and 0.018 or 0.024
    self.points[#self.points + 1] = {
      x = plane.x, y = plane.y, dir = dir, age = 0,
      width = 9 + math.min(18, speed * 0.055),
      phase = love.math.random() * math.pi * 2,
    }
    if #self.points > MAX_POINTS then table.remove(self.points, 1) end
  end
end

local function addStrip(mesh, points, widthScale, alphaScale, time)
  local verts = {}
  local n = #points
  for i = 1, n do
    local p = points[i]
    local fade = math.max(0, 1 - p.age / LIFETIME)
    fade = fade * fade
    local wobble = math.sin(time * 3.4 + p.phase + i * 0.22) * 3.8
    local s, c = math.sin(p.dir), math.cos(p.dir)
    local nx, ny = -s, c
    local w = p.width * widthScale * (0.72 + 0.28 * fade)
    verts[#verts + 1] = {
      p.x + nx * (w + wobble), p.y + ny * (w + wobble), 0, 0.5,
      1, 1, 1, fade * alphaScale,
    }
    verts[#verts + 1] = {
      p.x - nx * (w - wobble), p.y - ny * (w - wobble), 1, 0.5,
      1, 1, 1, fade * alphaScale,
    }
  end
  mesh:setVertices(verts)
  return n * 2
end

function CloudWake:draw()
  local points = self.points
  if #points < 3 then return end
  local tex = texture()
  if not self.mesh then
    self.mesh = love.graphics.newMesh(MAX_POINTS * 2, "strip", "dynamic")
    self.mesh:setTexture(tex)
  end
  if not self.innerMesh then
    self.innerMesh = love.graphics.newMesh(MAX_POINTS * 2, "strip", "dynamic")
    self.innerMesh:setTexture(tex)
  end
  if not self.broadMesh then
    self.broadMesh = love.graphics.newMesh(MAX_POINTS * 2, "strip", "dynamic")
    self.broadMesh:setTexture(tex)
  end
  love.graphics.push("all")
  love.graphics.setBlendMode("alpha")
  local n = addStrip(self.broadMesh, points, 1.9, 0.08, self.time)
  self.broadMesh:setDrawRange(1, n)
  love.graphics.setColor(0.94, 0.96, 0.95, 1)
  love.graphics.draw(self.broadMesh)
  n = addStrip(self.mesh, points, 1.0, 0.22, self.time)
  self.mesh:setDrawRange(1, n)
  love.graphics.setColor(0.94, 0.96, 0.95, 1)
  love.graphics.draw(self.mesh)
  n = addStrip(self.innerMesh, points, 0.52, 0.24, self.time)
  self.innerMesh:setDrawRange(1, n)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(self.innerMesh)
  love.graphics.pop()
end

return CloudWake
