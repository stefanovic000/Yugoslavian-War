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
    dist = math.sqrt(M.wrappedDist2(plane.x, plane.y, target.x, target.y, sim.w, sim.h))
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

  if speed < 100 or plane.stalling then
    -- Energy recovery beats everything else. Dive slightly and run full power.
    desired = 0.45
    throttle = 1
  elseif visible then
    local targetX = plane.x + M.delta(plane.x, target.x, sim.w)
    local targetY = plane.y + M.delta(plane.y, target.y, sim.h)
    local lead = 0.22
    local tx = M.wrap(targetX + target.vx * lead, sim.w)
    local ty = M.wrap(targetY + target.vy * lead, sim.h)
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
        state.patrolX = sim.rng:range(120, sim.w - 120)
        state.patrolY = sim.rng:range(80, sim.h - 80)
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
