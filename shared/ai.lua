-- Solo demo-plane AI. It is intentionally conservative: it manages throttle,
-- recovers from stalls, and patrols when clouds hide the player. It should be
-- shootable, but never simply fall out of the sky on its own.

local C = require("shared.constants")
local M = require("shared.mathx")
local Clouds = require("shared.clouds")

local AI = {}

AI.PROFILES = {
  rookie = { throttle = 0.68, fireDist = 250, aim = 0.10, lead = 0.12, wobble = 0.09, climb = 0.95 },
  veteran = { throttle = 0.78, fireDist = 360, aim = 0.16, lead = 0.22, wobble = 0.05, climb = 1.0 },
  ace = { throttle = 0.90, fireDist = 430, aim = 0.22, lead = 0.28, wobble = 0.02, climb = 1.0 },
}

function AI.newState(difficulty)
  return {
    difficulty = difficulty or "veteran",
    profile = AI.PROFILES[difficulty] or AI.PROFILES.veteran,
    patrolTimer = 0,
    patrolX = C.WORLD.w * 0.5,
    patrolY = C.WORLD.h * 0.5,
    lastSeenX = nil,
    lastSeenY = nil,
    wobble = 0,
  }
end

function AI.input(plane, target, sim, state, dt, difficulty)
  state = state or AI.newState(difficulty)
  local profile = AI.PROFILES[difficulty] or state.profile or AI.PROFILES.veteran
  state.profile = profile
  state.patrolTimer = state.patrolTimer - dt
  state.wobble = state.wobble + dt

  local speed = math.sqrt(plane.vx * plane.vx + plane.vy * plane.vy)
  local visible = false
  local dist = 9999

  if target and target.alive then
    dist = M.dist(plane.x, plane.y, target.x, target.y)
    visible = not Clouds.segmentBlocked(sim.clouds, plane.x, plane.y, target.x, target.y)
      and not Clouds.pointInside(sim.clouds, target.x, target.y)
    if visible then
      state.lastSeenX = target.x
      state.lastSeenY = target.y
    end
  end

  local desired
  local throttle = profile.throttle
  local fire = false
  local groundY = C.WORLD.groundY
  local wallLeft = C.WORLD.wallLeft
  local wallRight = C.WORLD.wallRight
  local groundClearance = groundY - plane.y
  local wallClearance = math.min(plane.x - wallLeft, wallRight - plane.x)
  local projectedX = plane.x + (plane.vx or 0) * 0.8
  local projectedY = plane.y + (plane.vy or 0) * 0.8
  local nearGround = groundClearance < 180 or projectedY > groundY - 100
  local hardGround = groundClearance < 65 or projectedY > groundY - 55
  local nearSky = plane.y < 150 or projectedY < 95
  local hardSky = plane.y < 65 or projectedY < 40
  local nearWall = wallClearance < 170 or projectedX < wallLeft + 100 or projectedX > wallRight - 100

  if hardGround then
    -- Emergency recovery: full power, nose hard toward open sky.
    desired = M.angleTo(plane.x, plane.y, plane.x, groundY - 240)
    throttle = 1
  elseif hardSky then
    -- Do not let the bot pin itself against the top of the arena.
    desired = M.angleTo(plane.x, plane.y, plane.x,
      math.min(groundY - 220, plane.y + 240))
    throttle = 1
  elseif nearSky then
    -- Recover toward the middle of the arena and lose altitude together.
    desired = M.angleTo(plane.x, plane.y, C.WORLD.w * 0.5,
      math.min(groundY - 180, plane.y + 190))
    throttle = 1
  elseif nearWall then
    -- Steer back to the middle and gain height before chasing again.
    local dir = (plane.x < C.WORLD.w * 0.5) and 1 or -1
    desired = M.angleTo(plane.x, plane.y, plane.x + dir * 180, plane.y - 110)
    throttle = 1
  elseif nearGround then
    desired = 0.45
    throttle = 1
  elseif visible then
    local targetX = target.x
    local targetY = target.y
    local lead = profile.lead
    local tx = targetX + target.vx * lead
    local ty = math.max(70, math.min(targetY + target.vy * lead, groundY - 150))
    desired = M.angleTo(plane.x, plane.y, tx, ty)

    if dist < 80 then
      desired = desired + math.pi * 0.5
      throttle = 0.9
    elseif dist > 300 then
      throttle = profile.throttle
    end

    local aimDiff = math.abs(M.angleDiff(plane.angle, M.angleTo(plane.x, plane.y, targetX, targetY)))
    fire = speed > 90 and dist < profile.fireDist and aimDiff < profile.aim and plane.ammo > 0
  else
    if state.lastSeenX and state.patrolTimer <= 0 then
      desired = M.angleTo(plane.x, plane.y, state.lastSeenX, state.lastSeenY)
      state.patrolTimer = 2.5
      state.lastSeenX = nil
      state.lastSeenY = nil
    else
      if state.patrolTimer <= 0 then
        state.patrolX = sim.rng:range(wallLeft + 140, wallRight - 140)
        local maxPatrolY = math.min(sim.h - 80, groundY - 170)
        state.patrolY = sim.rng:range(100, maxPatrolY)
        state.patrolTimer = sim.rng:range(3, 6)
      end
      desired = M.angleTo(plane.x, plane.y, state.patrolX, state.patrolY)
    end
    if speed > 180 then throttle = 0.55 end
  end

  -- A little wobble keeps the bots from looking robotic.
  desired = desired + math.sin(state.wobble * 0.9) * profile.wobble

  local diff = M.angleDiff(plane.angle, desired)
  local authority = (hardGround or nearGround or nearWall) and 5.0 or 3.6
  local pitch = M.clamp(diff * authority, -1, 1)

  return {
    pitch = pitch,
    throttle = throttle,
    fire = fire,
  }
end

return AI
