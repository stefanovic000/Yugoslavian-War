-- Side-view flight model. Deliberately shared by the client (prediction) and
-- the dedicated server (authority), so the same inputs produce the same result.
--
-- Controls: pitch -1 = nose up, +1 = nose down; throttle 0..1; fire boolean.

local C = require("shared.constants")
local M = require("shared.mathx")

local Flight = {}
local P = C.PLANE

local function partFactor(plane, part)
  local hp = plane.parts[part] or 0
  return M.clamp(hp / P.partHp, 0, 1)
end

function Flight.new(opts)
  opts = opts or {}
  local maxHp = opts.hp or P.hp
  local plane = {
    id = opts.id,
    name = opts.name or "Pilot",
    team = opts.team or opts.id or 1,
    x = opts.x or C.WORLD.w * 0.5,
    y = opts.y or C.WORLD.h * 0.5,
    vx = opts.vx or math.cos(opts.angle or 0) * (opts.speed or 120),
    vy = opts.vy or math.sin(opts.angle or 0) * (opts.speed or 120),
    angle = opts.angle or 0,
    radius = P.radius,
    throttle = opts.throttle or 0.65,
    pitchVel = 0,
    hp = maxHp,
    maxHp = maxHp,
    baseHp = maxHp,
    parts = {
      engine = P.partHp,
      wing = P.partHp,
      tail = P.partHp,
      guns = P.partHp,
    },
    ammo = P.ammo,
    maxAmmo = P.maxAmmo,
    fireTimer = 0,
    heat = 0,
    jammed = 0,
    ramCooldown = 0,
    alive = true,
    stalling = false,
    stallTimer = 0,
    hitFlash = 0,
    invuln = opts.invuln or 1.5,
    ai = nil,
    lastHitPart = nil,
  }
  return plane
end

function Flight.reset(plane, x, y, angle)
  plane.x, plane.y = x, y
  plane.angle = angle or 0
  plane.vx = math.cos(plane.angle) * 120
  plane.vy = math.sin(plane.angle) * 120
  plane.throttle = 0.65
  plane.pitchVel = 0
  plane.hp = plane.baseHp or P.hp
  plane.maxHp = plane.hp
  plane.parts.engine = P.partHp
  plane.parts.wing = P.partHp
  plane.parts.tail = P.partHp
  plane.parts.guns = P.partHp
  plane.ammo = P.ammo
  plane.maxAmmo = P.maxAmmo
  plane.fireTimer = 0
  plane.heat = 0
  plane.jammed = 0
  plane.ramCooldown = 0
  plane.alive = true
  plane.stalling = false
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
  local guns = Flight.gunFactor(plane)
  return P.fireInterval * (1 + (1 - guns) * 1.4)
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
  local stalling = speed < P.stallSpeed
  local authority = M.clamp((speed - 25) / (P.stallSpeed * 1.6 - 25), 0.18, 1)
  authority = authority * wing * (0.65 + 0.35 * tail)

  -- A stalled wing still gives enough elevator authority to snap the nose
  -- around, but the aircraft immediately starts falling. That makes a
  -- deliberate stall a risky reversal rather than just a dead stick.
  if stalling then authority = math.max(authority, 0.55) end

  local pitch = M.clamp(input.pitch or 0, -1, 1)
  local targetPitchVel = pitch * P.pitchRate * authority
  plane.pitchVel = plane.pitchVel + (targetPitchVel - plane.pitchVel) * (1 - math.exp(-12 * dt))
  plane.angle = M.wrapAngle(plane.angle + plane.pitchVel * dt)

  plane.stalling = stalling
  if plane.stalling then
    plane.stallTimer = plane.stallTimer + dt
    -- Nose falls toward screen-down when there is not enough airspeed. This is
    -- screen-relative, so it works whether the plane is flying left or right.
    local diff = M.angleDiff(plane.angle, math.pi * 0.5)
    local severity = 1 - M.clamp(speed / P.stallSpeed, 0, 1) * 0.6
    plane.angle = M.wrapAngle(plane.angle
      + M.clamp(diff * 3, -1, 1) * P.stallTorque * severity * dt)
  else
    plane.stallTimer = 0
  end

  local fx, fy = math.cos(plane.angle), math.sin(plane.angle)

  -- Thrust along the nose. A small amount of idle thrust means the engine is
  -- never completely dead, but closing the throttle still adds engine braking.
  local thrust = (0.04 + 0.96 * plane.throttle) * P.thrust * Flight.engineFactor(plane)
  plane.vx = plane.vx + fx * thrust * dt
  plane.vy = plane.vy + fy * thrust * dt

  -- Gravity.
  plane.vy = plane.vy + P.gravity * dt

  -- Wing lift. Linear near stall; throttle is deliberately not part of this
  -- term. Throttle changes thrust/drag, not raw lift, so W/S does not feel like
  -- a second pitch control.
  local liftFrac = M.clamp(speed / P.cruiseSpeed, 0, 1.0)
    * (math.abs(math.cos(plane.angle)) ^ 0.5) * wing
  -- Climbing steeply costs lift and energy. Without this a sustained vertical
  -- pull would be a free elevator to the ceiling.
  local climb = math.max(0, -plane.vy) / math.max(speed, 1)
  liftFrac = liftFrac * (1 - P.climbLiftCut * climb)
  local lift = P.gravity * liftFrac
  plane.vy = plane.vy - lift * dt

  -- Closed throttle adds engine braking. The aircraft bleeds speed, loses lift
  -- and falls without making the throttle itself act like an elevator.
  local velocityAngle = math.atan2(plane.vy, plane.vx)
  local slip = math.abs(M.angleDiff(velocityAngle, plane.angle))
  local dragCoef = P.drag + (1 - plane.throttle) * P.engineBrake
    + slip * P.slipDrag + climb * P.climbDrag
    + math.abs(plane.pitchVel) * P.turnDrag
  local drag = dragCoef * speed
  plane.vx = plane.vx - plane.vx * drag * dt
  plane.vy = plane.vy - plane.vy * drag * dt

  -- The airframe follows the nose, but only partially. A hard pitch input
  -- creates real sideslip, and sideslip costs speed. Energy management and
  -- aiming matter instead of the nose dragging the velocity around instantly.
  local newSpeed = Flight.speed(plane)
  if newSpeed > 10 then
    velocityAngle = math.atan2(plane.vy, plane.vx)
    local follow = 1 - math.exp(-5.0 * authority * dt)
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

  plane.x = M.wrap(plane.x + plane.vx * dt, C.WORLD.w)
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

