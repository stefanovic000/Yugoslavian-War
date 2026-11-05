-- Deterministic world simulation. The dedicated server owns it; solo play uses
-- the same code locally. Rendering and UI never mutate it directly.

local C = require("shared.constants")
local M = require("shared.mathx")
local Rng = require("shared.rng")
local Flight = require("shared.flight")
local Combat = require("shared.combat")
local Clouds = require("shared.clouds")
local Shapes = require("shared.cloud_shapes")
local Terrain = require("shared.terrain")

local Sim = {}
Sim.__index = Sim

function Sim.new(opts)
  opts = opts or {}
  local seed = opts.seed or 1
  return setmetatable({
    w = opts.w or C.WORLD.w,
    h = opts.h or C.WORLD.h,
    planes = {},
    planeOrder = {},
    bullets = {},
    pickups = {},
    clouds = Clouds.new(seed, opts.cloudCount),
    rng = Rng.new(seed + 91),
    time = 0,
    pickupTimer = 6,
    nextBulletId = 1,
    nextSmokeId = 1000,
    events = {},
    teamMode = opts.teamMode == true,
    lagByOwner = {},
  }, Sim)
end

function Sim:addPlane(opts)
  local plane = Flight.new(opts)
  plane.id = opts.id or (#self.planeOrder + 1)
  plane.team = opts.team or plane.id
  plane.x = M.clamp(plane.x, C.WORLD.wallLeft + plane.radius, C.WORLD.wallRight - plane.radius)
  plane.y = M.clamp(plane.y, plane.radius, Terrain.height(plane.x) - C.PLANE.groundOffset)
  plane.history = { { t = self.time, x = plane.x, y = plane.y, a = plane.angle } }
  self.planes[plane.id] = plane
  self.planeOrder[#self.planeOrder + 1] = plane.id
  return plane
end

function Sim:poseAt(plane, targetTime)
  local history = plane.history
  if not history or #history == 0 then
    return { x = plane.x, y = plane.y, a = plane.angle }
  end
  local prev = history[1]
  local next = history[#history]
  for _, h in ipairs(history) do
    if h.t <= targetTime then prev = h end
    if h.t >= targetTime then next = h; break end
  end
  if prev == next or next.t <= prev.t then
    return { x = prev.x, y = prev.y, a = prev.a }
  end
  local k = M.clamp((targetTime - prev.t) / (next.t - prev.t), 0, 1)
  return {
    x = prev.x + (next.x - prev.x) * k,
    y = prev.y + (next.y - prev.y) * k,
    a = prev.a + M.angleDiff(prev.a, next.a) * k,
  }
end

function Sim:removePlane(id)
  if not self.planes[id] then return end
  self.planes[id] = nil
  for i, pid in ipairs(self.planeOrder) do
    if pid == id then
      table.remove(self.planeOrder, i)
      break
    end
  end
end

function Sim:getPlane(id)
  return self.planes[id]
end

function Sim:spawnBullet(plane, aimAngle)
  local spread = (self.rng:next() - 0.5) * 2 * C.BULLET.spread
  local angle = plane.angle + spread
  if aimAngle then
    local diff = M.angleDiff(plane.angle, aimAngle)
    if math.abs(diff) <= 0.35 then angle = aimAngle + spread end
  end
  local fx, fy = math.cos(angle), math.sin(angle)
  local nx, ny = Combat.toWorld(plane, 18, 0)
  local x = nx
  local y = ny

  local bullet = {
    id = self.nextBulletId,
    owner = plane.id,
    team = plane.team,
    x = x,
    y = y,
    px = x,
    py = y,
    sx = plane.x,
    sy = plane.y,
    firstStep = true,
    vx = fx * C.BULLET.speed,
    vy = fy * C.BULLET.speed,
    life = C.BULLET.life,
    damage = C.BULLET.damage,
    radius = C.BULLET.radius,
    dead = false,
  }
  self.nextBulletId = self.nextBulletId + 1
  self.bullets[#self.bullets + 1] = bullet
  self.events[#self.events + 1] = {
    type = "shot", id = bullet.id, owner = plane.id,
    x = x, y = y, angle = angle,
  }
  return bullet
end

function Sim:tryFire(plane, input)
  if not input or not input.fire then return false end
  if not Flight.canFire(plane) then return false end
  plane.ammo = math.max(0, plane.ammo - 1)
  plane.fireTimer = Flight.fireInterval(plane)
  plane.heat = math.min(1, (plane.heat or 0) + C.GUN.heatPerShot)
  if plane.heat >= 1 then
    plane.jammed = C.GUN.jamTime
    self.events[#self.events + 1] = {
      type = "overheat", player = plane.id,
      x = plane.x, y = plane.y,
    }
  end
  self:spawnBullet(plane, input.aim)
  return true
end

function Sim:spawnPickup(x)
  if #self.pickups >= C.PICKUP.max then return end
  local pickup = {
    id = #self.pickups + 1,
    x = x or self.rng:range(C.WORLD.wallLeft + 50, C.WORLD.wallRight - 50),
    y = -12,
    vy = C.PICKUP.fallSpeed,
    phase = self.rng:range(0, math.pi * 2),
    radius = C.PICKUP.radius,
  }
  self.pickups[#self.pickups + 1] = pickup
  return pickup
end

function Sim:addSmokeCloud(x, y, scale)
  scale = scale or 1
  local id = self.nextSmokeId
  self.nextSmokeId = self.nextSmokeId + 1
  local r = 60 * scale
  local variant = self.rng:int(1, 3)
  local cloud = {
    id = id,
    x = x, y = y, r = r, speed = self.rng:range(-4, 4),
    alpha = 0.94, baseAlpha = 0.94,
    variant = variant,
    smoke = true,
    life = 2.6, maxLife = 2.6,
    tint = { 0.30, 0.27, 0.24 },
    puffs = Shapes.puffs(variant, r),
  }
  table.insert(self.clouds.list, cloud)
  return cloud
end

function Sim:clearSmokeClouds()
  for i = #self.clouds.list, 1, -1 do
    if self.clouds.list[i].smoke then table.remove(self.clouds.list, i) end
  end
end

function Sim:step(inputs, dt)
  local events = {}
  self.events = events
  self.time = self.time + dt

  for _, id in ipairs(self.planeOrder) do
    local plane = self.planes[id]
    if plane and plane.alive then
      plane.prevX, plane.prevY, plane.prevAngle = plane.x, plane.y, plane.angle
      local input = inputs and inputs[id]
      Flight.step(plane, input or plane.lastInput, dt)
      plane.lastInput = input or plane.lastInput
      local ground = Terrain.height(plane.x)
      if plane.alive and plane.y + C.PLANE.groundOffset >= ground then
        plane.y = ground - C.PLANE.groundOffset
        plane.hp = 0
        plane.alive = false
        events[#events + 1] = {
          type = "crash", reason = "ground", victim = plane.id,
          x = plane.x, y = C.WORLD.groundY,
        }
      elseif plane.alive
        and (plane.x <= C.WORLD.wallLeft + plane.radius
          or plane.x >= C.WORLD.wallRight - plane.radius) then
        plane.x = M.clamp(plane.x, C.WORLD.wallLeft + plane.radius,
          C.WORLD.wallRight - plane.radius)
        plane.hp = 0
        plane.alive = false
        events[#events + 1] = {
          type = "crash", reason = "wall", victim = plane.id,
          x = plane.x, y = plane.y,
        }
      else
        self:tryFire(plane, input)
      end

      plane.history = plane.history or {}
      plane.history[#plane.history + 1] = {
        t = self.time, x = plane.x, y = plane.y, a = plane.angle,
      }
      if #plane.history > 45 then table.remove(plane.history, 1) end
    end
  end

  -- Bullets.
  local i = 1
  while i <= #self.bullets do
    local b = self.bullets[i]
    if b.firstStep then
      -- The muzzle is ahead of the airframe. Sweep the first shot from the
      -- aircraft centre so a close target inside the muzzle offset is not skipped.
      b.px, b.py = b.sx or b.x, b.sy or b.y
      b.firstStep = nil
    else
      b.px, b.py = b.x, b.y
    end
    b.x = b.x + b.vx * dt
    b.y = b.y + b.vy * dt
    b.life = b.life - dt

    if b.life <= 0
      or b.x < C.WORLD.wallLeft - 10 or b.x > C.WORLD.wallRight + 10
      or b.y < -20 or b.y > Terrain.height(b.x) + 10 then
      b.dead = true
    else
      for _, pid in ipairs(self.planeOrder) do
        local plane = self.planes[pid]
        local owner = self.planes[b.owner]
        if plane and plane.alive and plane.id ~= b.owner
          and not (self.teamMode and owner and owner.team == plane.team) then
          local part = Combat.bulletHitsMovingPlane(b, plane,
            plane.prevX, plane.prevY, plane.prevAngle, self.w, self.h)
          local lag = self.lagByOwner[b.owner] or 0
          if not part and lag > 0.02 then
            -- Match the shooter's view: remote aircraft are rendered slightly
            -- behind the authoritative position by interpolation and RTT.
            -- Check a small window too, because render smoothing is not exact.
            for _, offset in ipairs({ 0, -0.04, 0.04 }) do
              local pose = self:poseAt(plane, self.time - lag + offset)
              part = Combat.bulletHitsPlaneAt(b, plane, pose.x, pose.y, pose.a,
                self.w, self.h)
              if part then break end
            end
          end
          if part then
            local applied = Flight.applyDamage(plane, part, b.damage)
            events[#events + 1] = {
              type = "hit", owner = b.owner, victim = plane.id, part = part,
              x = b.x, y = b.y, damage = b.damage, bulletId = b.id,
            }
            if applied and not plane.alive then
              events[#events + 1] = {
                type = "kill", victim = plane.id, killer = b.owner,
                x = plane.x, y = plane.y,
              }
            end
            b.dead = true
            break
          end
        end
      end
    end

    if b.dead then
      self.bullets[i] = self.bullets[#self.bullets]
      self.bullets[#self.bullets] = nil
    else
      i = i + 1
    end
  end

  -- Plane ramming (rare, but makes the collision model consistent).
  for a = 1, #self.planeOrder do
    for b = a + 1, #self.planeOrder do
      local pa = self.planes[self.planeOrder[a]]
      local pb = self.planes[self.planeOrder[b]]
      if pa and pb and pa.alive and pb.alive
        and not (self.teamMode and pa.team == pb.team)
        and Combat.planesRam(pa, pb, self.w, self.h) then
        local d = M.delta(pa.x, pb.x, self.w)
        local push = (d >= 0) and 1 or -1
        pa.x = M.wrap(pa.x - push * 4, self.w)
        pb.x = M.wrap(pb.x + push * 4, self.w)
        -- Damage once per second, not once per overlapping tick.
        if (pa.ramCooldown or 0) <= 0 and (pb.ramCooldown or 0) <= 0 then
          pa.ramCooldown = 1
          pb.ramCooldown = 1
          Flight.applyDamage(pa, "engine", 16)
          Flight.applyDamage(pb, "engine", 16)
          events[#events + 1] = {
            type = "ram", a = pa.id, b = pb.id,
            x = (pa.x + pb.x) * 0.5, y = (pa.y + pb.y) * 0.5,
          }
          if not pa.alive then
            events[#events + 1] = {
              type = "kill", victim = pa.id, killer = pb.id,
              x = pa.x, y = pa.y,
            }
          end
          if not pb.alive then
            events[#events + 1] = {
              type = "kill", victim = pb.id, killer = pa.id,
              x = pb.x, y = pb.y,
            }
          end
        end
      end
    end
  end

  -- Parachute ammo crates.
  self.pickupTimer = self.pickupTimer - dt
  if self.pickupTimer <= 0 then
    self:spawnPickup()
    self.pickupTimer = C.PICKUP.interval
  end

  i = 1
  while i <= #self.pickups do
    local pickup = self.pickups[i]
    pickup.y = pickup.y + pickup.vy * dt
    pickup.x = M.clamp(pickup.x + math.sin(self.time * 0.8 + pickup.phase) * 5 * dt,
      C.WORLD.wallLeft + pickup.radius, C.WORLD.wallRight - pickup.radius)

    local taken = false
    for _, pid in ipairs(self.planeOrder) do
      local plane = self.planes[pid]
      if plane and plane.alive and Combat.pickupHitsPlane(pickup, plane, self.w, self.h) then
        plane.ammo = math.min(plane.maxAmmo, plane.ammo + C.PICKUP.ammo)
        events[#events + 1] = {
          type = "pickup", player = plane.id, x = pickup.x, y = pickup.y, ammo = C.PICKUP.ammo,
        }
        taken = true
        break
      end
    end

    if taken or pickup.y > self.h + 24 then
      self.pickups[i] = self.pickups[#self.pickups]
      self.pickups[#self.pickups] = nil
    else
      i = i + 1
    end
  end

  Clouds.update(self.clouds, dt)
  return events
end

function Sim:resetPickups()
  self.pickups = {}
  self.pickupTimer = 6
end

function Sim:resetBullets()
  self.bullets = {}
  self.nextBulletId = 1
end

return Sim


