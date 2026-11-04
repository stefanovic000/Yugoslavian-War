-- Solo demo-plane AI. It is intentionally conservative: it manages throttle,
-- recovers from stalls, and patrols when clouds hide the player. It should be
-- shootable, but never simply fall out of the sky on its own.

local C = require("shared.constants")
local M = require("shared.mathx")
local Clouds = require("shared.clouds")

local AI = {}

function AI.newState()
  return {
    patrolTimer = 0,
    patrolX = C.WORLD.w * 0.5,
    patrolY = C.WORLD.h * 0.5,
    lastSeenX = nil,
    lastSeenY = nil,
    wobble = 0,
  }
end

function AI.input(plane, target, sim, state, dt)
  state = state or AI.newState()
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
  local throttle = 0.78
  local fire = false
  local groundClearance = C.WORLD.groundY - plane.y
  local wallClearance = math.min(
    plane.x - C.WORLD.wallLeft,
    C.WORLD.wallRight - plane.x
  )

  if groundClearance < 110 then
    -- Pull up with priority over chasing. A demo plane should never plow into
    -- the deck while following a target or a patrol point.
    local noseX = plane.x + math.cos(plane.angle) * 120
    desired = M.angleTo(plane.x, plane.y, noseX, C.WORLD.groundY - 170)
    throttle = 1
  elseif wallClearance < 120 then
    -- Old buildings at the sides are solid; steer back toward open air.
    local dir = (plane.x < C.WORLD.w * 0.5) and 1 or -1
    desired = M.angleTo(plane.x, plane.y, plane.x + dir * 160, plane.y - 90)
    throttle = 1
  elseif speed < 100 or plane.stalling then
    -- Energy recovery beats everything else. Dive slightly and run full power.
    desired = 0.45
    throttle = 1
  elseif visible then
    local targetX = target.x
    local targetY = target.y
    local lead = 0.22
    local tx = targetX + target.vx * lead
    local ty = targetY + target.vy * lead
    desired = M.angleTo(plane.x, plane.y, tx, ty)

    if dist < 80 then
      desired = desired + math.pi * 0.5
      throttle = 0.9
    elseif dist > 300 then
      throttle = 0.9
    end

    local aimDiff = math.abs(M.angleDiff(plane.angle, M.angleTo(plane.x, plane.y, targetX, targetY)))
    fire = speed > 90 and dist < 360 and aimDiff < 0.16 and plane.ammo > 0
  else
    if state.lastSeenX and state.patrolTimer <= 0 then
      desired = M.angleTo(plane.x, plane.y, state.lastSeenX, state.lastSeenY)
      state.patrolTimer = 2.5
      state.lastSeenX = nil
      state.lastSeenY = nil
    else
      if state.patrolTimer <= 0 then
        state.patrolX = sim.rng:range(C.WORLD.wallLeft + 120, C.WORLD.wallRight - 120)
        local maxPatrolY = math.min(sim.h - 80, C.WORLD.groundY - 120)
        state.patrolY = sim.rng:range(80, maxPatrolY)
        state.patrolTimer = sim.rng:range(3, 6)
      end
      desired = M.angleTo(plane.x, plane.y, state.patrolX, state.patrolY)
    end
    if speed > 180 then throttle = 0.55 end
  end

  -- A little wobble keeps the demo plane from looking robotic.
  desired = desired + math.sin(state.wobble * 0.9) * 0.05

  local diff = M.angleDiff(plane.angle, desired)
  local pitch = M.clamp(diff * 3.2, -1, 1)

  return {
    pitch = pitch,
    throttle = throttle,
    fire = fire,
  }
end

return AI
