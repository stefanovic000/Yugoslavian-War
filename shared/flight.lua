-- Side-view flight model. Deliberately shared by the client (prediction) and
-- the dedicated server (authority), so the same inputs produce the same result.
--
-- Controls: pitch -1 = nose up, +1 = nose down; throttle 0..1; fire boolean.

local C = require("shared.constants")
local M = require("shared.mathx")
local Aircraft = require("shared.aircraft")

local Flight = {}
local P = C.PLANE

local function specOf(plane)
  return (plane.spec and plane.spec.stats) or P
end

local function partFactor(plane, part)
  local S = specOf(plane)
  local hp = plane.parts[part] or 0
  return M.clamp(hp / S.partHp, 0, 1)
end

function Flight.new(opts)
  opts = opts or {}
  local spec = Aircraft.get(opts.planeType or opts.aircraft)
  local S = spec.stats
  local maxHp = opts.hp or S.hp
  local plane = {
    id = opts.id,
    name = opts.name or "Pilot",
    planeType = spec.id,
    spec = spec,
    team = opts.team or opts.id or 1,
    x = opts.x or C.WORLD.w * 0.5,
    y = opts.y or C.WORLD.h * 0.5,
    vx = opts.vx or math.cos(opts.angle or 0) * (opts.speed or 120),
    vy = opts.vy or math.sin(opts.angle or 0) * (opts.speed or 120),
    angle = opts.angle or 0,
    radius = S.radius,
    throttle = opts.throttle or 0.65,
    pitchVel = 0,
    hp = maxHp,
    maxHp = maxHp,
    baseHp = maxHp,
    parts = {
      engine = S.partHp,
      wing = S.partHp,
      tail = S.partHp,
      guns = S.partHp,
    },
    ammo = S.ammo,
    maxAmmo = S.maxAmmo,
    fireTimer = 0,
    heat = 0,
    jammed = 0,
    ramCooldown = 0,
    alive = true,
    stalling = false,
    stallSeverity = 0,
    stallTimer = 0,
    hitFlash = 0,
    invuln = opts.invuln or 1.5,
    ai = nil,
    lastHitPart = nil,
  }
  return plane
end

function Flight.reset(plane, x, y, angle)
  local S = specOf(plane)
  plane.x, plane.y = x, y
  plane.angle = angle or 0
  plane.vx = math.cos(plane.angle) * 120
  plane.vy = math.sin(plane.angle) * 120
  plane.throttle = 0.65
  plane.pitchVel = 0
  plane.hp = plane.baseHp or S.hp
  plane.maxHp = plane.hp
  plane.parts.engine = S.partHp
  plane.parts.wing = S.partHp
  plane.parts.tail = S.partHp
  plane.parts.guns = S.partHp
  plane.ammo = S.ammo
  plane.maxAmmo = S.maxAmmo
  plane.fireTimer = 0
  plane.heat = 0
  plane.jammed = 0
  plane.ramCooldown = 0
  plane.alive = true
  plane.stalling = false
  plane.stallSeverity = 0
  plane.stallTimer = 0
  plane.hitFlash = 0
  plane.invuln = 1.5
  plane.lastHitPart = nil
end

function Flight.forward(angle)
  return math.cos(angle), math.sin(angle)
end

function Flight.speed(plane)
  return math.sqrt(plane.vx * plane.vx + plane.vy * plane.vy)
end

function Flight.engineFactor(plane)
  return 0.25 + 0.75 * partFactor(plane, "engine")
end

function Flight.wingFactor(plane)
  return 0.35 + 0.65 * partFactor(plane, "wing")
end

function Flight.tailFactor(plane)
  return 0.45 + 0.55 * partFactor(plane, "tail")
end

function Flight.gunFactor(plane)
  return partFactor(plane, "guns")
end

function Flight.canFire(plane)
  return plane.alive and plane.ammo > 0 and plane.parts.guns > 0
    and plane.fireTimer <= 0 and (plane.jammed or 0) <= 0
    and (plane.heat or 0) < 1
end

function Flight.fireInterval(plane)
  local S = specOf(plane)
  local guns = Flight.gunFactor(plane)
  return S.fireInterval * (1 + (1 - guns) * 1.4)
end

function Flight.applyDamage(plane, part, amount)
  if not plane.alive or plane.invuln > 0 or plane.god then return false end
  if not plane.parts[part] then part = "engine" end

  plane.hp = math.max(0, plane.hp - amount)
  plane.parts[part] = math.max(0, plane.parts[part] - amount * 1.35)
  plane.hitFlash = 0.14
  plane.lastHitPart = part

  if plane.hp <= 0 then
    plane.alive = false
  end
  return true
end

function Flight.step(plane, input, dt)
  if not plane.alive then return end
  local P = specOf(plane)

  if (plane.jammed or 0) > 0 then
    plane.jammed = plane.jammed - dt
    if plane.jammed < 0 then plane.jammed = 0 end
  end
  plane.heat = M.clamp((plane.heat or 0) - C.GUN.coolRate * dt, 0, 1)
  input = input or {}

  local speed = Flight.speed(plane)
  plane.throttle = M.clamp(input.throttle or plane.throttle, 0, 1)

  local wing = Flight.wingFactor(plane)
  local tail = Flight.tailFactor(plane)
  local velocityAngle = math.atan2(plane.vy, plane.vx)
  local aoa = math.abs(M.angleDiff(plane.angle, velocityAngle))
  local speedSeverity = M.clamp((P.stallSpeed - speed) / P.stallSpeed, 0, 1)
  local aoaSeverity = M.clamp((aoa - P.stallAoa) / (P.stallAoa * 0.85), 0, 1)
  local lowSpeedFactor = M.clamp(
    (P.stallAoaSpeed - speed) / (P.stallAoaSpeed - P.stallSpeed), 0, 1)
  local stallSeverity = math.max(speedSeverity, aoaSeverity * lowSpeedFactor)
  local stalling = stallSeverity > 0.06

  local authority = M.clamp((speed - 20) / (P.stallSpeed * 1.6 - 20), 0.22, 1)
  authority = authority * wing * (0.65 + 0.35 * tail)
  authority = authority * (1 - 0.38 * stallSeverity)

  local pitch = M.clamp(input.pitch or 0, -1, 1)
  local targetPitchVel = pitch * P.pitchRate * authority
  plane.pitchVel = plane.pitchVel
    + (targetPitchVel - plane.pitchVel) * (1 - math.exp(-P.pitchDamping * dt))
  plane.angle = M.wrapAngle(plane.angle + plane.pitchVel * dt)

  plane.stalling = stalling
  plane.stallSeverity = stallSeverity
  if plane.stalling then
    plane.stallTimer = plane.stallTimer + dt
    -- The wing progressively loses lift; the resulting nose drop is driven by
    -- the current stall severity, not a binary low-speed switch.
    local diff = M.angleDiff(plane.angle, math.pi * 0.5)
    plane.angle = M.wrapAngle(plane.angle
      + M.clamp(diff * 2.0, -1, 1) * P.stallTorque
      * (0.25 + 0.75 * stallSeverity) * dt)
  else
    plane.stallTimer = 0
  end

  local fx, fy = math.cos(plane.angle), math.sin(plane.angle)
  local climb = math.max(0, -plane.vy) / math.max(speed, 1)

  -- Thrust along the nose. Climbing bleeds propeller efficiency, which prevents
  -- a sustained vertical climb from becoming a free elevator.
  local thrust = (0.04 + 0.96 * plane.throttle) * P.thrust
    * Flight.engineFactor(plane) * (1 - P.climbThrustCut * climb)
  plane.vx = plane.vx + fx * thrust * dt
  plane.vy = plane.vy + fy * thrust * dt

  -- Gravity.
  plane.vy = plane.vy + P.gravity * dt

  -- Wing lift. Linear near stall; throttle is deliberately not part of this
  -- term. Throttle changes thrust/drag, not raw lift, so W/S does not feel like
  -- a second pitch control.
  local liftFrac = M.clamp(speed / P.cruiseSpeed, 0, 1.0)
    * (math.abs(math.cos(plane.angle)) ^ 0.5) * wing
  liftFrac = liftFrac * (1 - P.stallLiftCut * stallSeverity)
  -- Climbing steeply costs lift and energy. Without this a sustained vertical
  -- pull would be a free elevator to the ceiling.
  liftFrac = liftFrac * (1 - P.climbLiftCut * climb)
  local lift = P.gravity * liftFrac
  plane.vy = plane.vy - lift * dt

  -- Closed throttle adds engine braking. The aircraft bleeds speed, loses lift
  -- and falls without making the throttle itself act like an elevator.
  velocityAngle = math.atan2(plane.vy, plane.vx)
  local slip = math.abs(M.angleDiff(velocityAngle, plane.angle))
  local dragCoef = P.drag + (1 - plane.throttle) * P.engineBrake
    + slip * P.slipDrag + climb * P.climbDrag
    + math.abs(plane.pitchVel) * P.turnDrag
    + stallSeverity * P.stallDrag
  local drag = dragCoef * speed
  plane.vx = plane.vx - plane.vx * drag * dt
  plane.vy = plane.vy - plane.vy * drag * dt

  -- The airframe follows the nose, but only partially. A hard pitch input
  -- creates real sideslip, and sideslip costs speed. Energy management and
  -- aiming matter instead of the nose dragging the velocity around instantly.
  local newSpeed = Flight.speed(plane)
  if newSpeed > 10 then
    velocityAngle = math.atan2(plane.vy, plane.vx)
    local follow = 1 - math.exp(-6.0 * authority * dt)
    velocityAngle = velocityAngle + M.angleDiff(velocityAngle, plane.angle) * follow
    plane.vx = math.cos(velocityAngle) * newSpeed
    plane.vy = math.sin(velocityAngle) * newSpeed
  end

  newSpeed = Flight.speed(plane)
  if newSpeed > P.maxSpeed then
    local k = P.maxSpeed / newSpeed
    plane.vx = plane.vx * k
    plane.vy = plane.vy * k
  end

  plane.x = plane.x + plane.vx * dt
  plane.y = plane.y + plane.vy * dt
  if plane.y < plane.radius then
    plane.y = plane.radius
    if plane.vy < 0 then plane.vy = 0 end
  end

  plane.fireTimer = math.max(0, plane.fireTimer - dt)
  plane.ramCooldown = math.max(0, (plane.ramCooldown or 0) - dt)
  plane.hitFlash = math.max(0, plane.hitFlash - dt)
  plane.invuln = math.max(0, plane.invuln - dt)
end

return Flight

