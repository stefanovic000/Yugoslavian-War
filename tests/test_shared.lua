local C = require("shared.constants")
local M = require("shared.mathx")
local Flight = require("shared.flight")
local Combat = require("shared.combat")

local cases = {}

local function newSim(seed)
  local Sim = require("shared.sim")
  return Sim.new({ seed = seed or 1 })
end

cases[#cases + 1] = {
  name = "level flight holds altitude under full power",
  fn = function()
    local sim = newSim(7)
    local p = sim:addPlane({ id = 1, x = 400, y = 225, angle = 0, speed = 165, throttle = 1 })
    local startY = p.y
    local input = { throttle = 1, pitch = 0, fire = false }
    for _ = 1, 180 do
      sim:step({ [1] = input }, C.TICK)
    end
    assert(math.abs(p.y - startY) < 20, "altitude drifted by " .. (p.y - startY))
    assert(math.abs(Flight.speed(p) - 170) < 20, "speed drifted to " .. Flight.speed(p))
  end,
}

cases[#cases + 1] = {
  name = "cutting throttle loses altitude fast",
  fn = function()
    local sim = newSim(8)
    local p = sim:addPlane({ id = 1, x = 400, y = 225, angle = 0, speed = 120, throttle = 0 })
    local startY = p.y
    local minSpeed = 999
    for _ = 1, 300 do
      sim:step({ [1] = { throttle = 0, pitch = 0 } }, C.TICK)
      minSpeed = math.min(minSpeed, Flight.speed(p))
    end
    local dropped = math.abs(M.delta(startY, p.y, C.WORLD.h))
    assert(dropped > 80, "idle plane only dropped " .. dropped)
    assert(minSpeed < 85, "idle plane never got slow enough to stall")
  end,
}

cases[#cases + 1] = {
  name = "stall drops the nose when you do not recover",
  fn = function()
    local sim = newSim(9)
    local p = sim:addPlane({ id = 1, x = 400, y = 225, angle = 0, speed = 40, throttle = 0 })
    for _ = 1, 120 do
      sim:step({ [1] = { throttle = 0, pitch = 0 } }, C.TICK)
    end
    assert(p.angle > 0.2, "stall did not force the nose down: " .. p.angle)
  end,
}

cases[#cases + 1] = {
  name = "left-facing wing hitbox stays under the wing",
  fn = function()
    local sim = newSim(12)
    local p = sim:addPlane({ id = 1, x = 400, y = 225, angle = math.pi, speed = 120, invuln = 0 })
    -- Local wing tip is (-8, +4); at angle pi the mirrored sprite puts it at
    -- world (+8, +4). This is deliberately not computed with Combat.toWorld.
    local wx, wy = p.x + 8, p.y + 4
    local b = { x = wx, y = wy, px = wx, py = wy, owner = 2 }
    local part = Combat.bulletHitsPlane(b, p, C.WORLD.w, C.WORLD.h)
    assert(part == "wing", "left wing hitbox was " .. tostring(part))
  end,
}

cases[#cases + 1] = {
  name = "bullets spawn from the rotated nose",
  fn = function()
    local sim = newSim(11)
    local p = sim:addPlane({ id = 1, x = 400, y = 225, angle = 0.7, speed = 130 })
    sim:spawnBullet(p)
    local b = sim.bullets[1]
    assert(b, "no bullet spawned")
    local nx = p.x + math.cos(p.angle) * 18
    local ny = p.y + math.sin(p.angle) * 18
    local d = math.sqrt((b.x - nx) ^ 2 + (b.y - ny) ^ 2)
    assert(d < 0.2, "bullet spawned away from nose: " .. d)
  end,
}

cases[#cases + 1] = {
  name = "a sustained climb cannot keep gaining altitude",
  fn = function()
    local sim = newSim(10)
    local startY = 225
    local p = sim:addPlane({ id = 1, x = 400, y = startY, angle = 0, speed = 150, throttle = 1 })
    for _ = 1, 600 do
      sim:step({ [1] = { throttle = 1, pitch = -1 } }, C.TICK)
    end
    local delta = M.delta(startY, p.y, C.WORLD.h)
    assert(delta > -50, "sustained climb kept gaining altitude: " .. delta)
  end,
}

cases[#cases + 1] = {
  name = "flat-out throttle settles below max speed",
  fn = function()
    local sim = newSim(2)
    local p = sim:addPlane({ id = 1, x = 320, y = 180, angle = 0, speed = 140, throttle = 1 })
    for _ = 1, 600 do
      sim:step({ [1] = { throttle = 1, pitch = 0 } }, C.TICK)
    end
    local speed = Flight.speed(p)
    assert(speed > 150 and speed < 215, "unexpected top speed " .. speed)
  end,
}

cases[#cases + 1] = {
  name = "low speed stalls nose-down and gains speed",
  fn = function()
    local sim = newSim(3)
    local p = sim:addPlane({ id = 1, x = 320, y = 180, angle = 0, speed = 40, throttle = 0 })
    local startY = p.y
    local stalled = false
    for _ = 1, 240 do
      sim:step({ [1] = { throttle = 0, pitch = 0 } }, C.TICK)
      if p.stalling then stalled = true end
    end
    assert(stalled, "plane never flagged a stall")
    assert(p.y > startY or p.vy > 40, "stalled plane did not sink")
    assert(math.sin(p.angle) > 0.2, "nose did not fall toward screen-down")
  end,
}

cases[#cases + 1] = {
  name = "side walls stop and crash the plane",
  fn = function()
    local sim = newSim(4)
    local p = sim:addPlane({ id = 1, x = 60, y = 180, angle = math.pi, speed = 170 })
    local crash = false
    for _ = 1, 60 do
      for _, e in ipairs(sim:step({ [1] = { throttle = 0.6, pitch = 0 } }, C.TICK)) do
        if e.type == "crash" and e.reason == "wall" and e.victim == p.id then crash = true end
      end
    end
    assert(not p.alive, "plane did not crash into the side wall")
    assert(crash, "wall crash event missing")
    assert(p.x >= C.WORLD.wallLeft + C.PLANE.radius, "plane crossed the side wall")
  end,
}

cases[#cases + 1] = {
  name = "module damage changes flight",
  fn = function()
    local sim = newSim(5)
    local a = sim:addPlane({ id = 1, x = 100, y = 180, angle = 0, speed = 160 })
    local b = sim:addPlane({ id = 2, x = 500, y = 180, angle = 0, speed = 160 })
    b.parts.engine = 0
    b.parts.wing = 0
    assert(Flight.engineFactor(b) < Flight.engineFactor(a))
    assert(Flight.wingFactor(b) < Flight.wingFactor(a))
    assert(Flight.tailFactor(b) == Flight.tailFactor(a))
  end,
}

cases[#cases + 1] = {
  name = "deterministic simulation",
  fn = function()
    local function run()
      local sim = newSim(11)
      local p = sim:addPlane({ id = 1, x = 200, y = 150, angle = 0, speed = 170 })
      local input = { throttle = 0.8, pitch = -0.4, fire = true }
      for _ = 1, 300 do
        sim:step({ [1] = input }, C.TICK)
      end
      return string.format("%.5f %.5f %.5f %.5f %d", p.x, p.y, p.angle, Flight.speed(p), p.ammo)
    end
    assert(run() == run(), "simulation is not deterministic")
  end,
}

cases[#cases + 1] = {
  name = "good hitboxes map parts",
  fn = function()
    local sim = newSim(6)
    local p = sim:addPlane({ id = 1, x = 320, y = 180, angle = 0, invuln = 0 })

    local function shootAt(lx, ly, span)
      span = span or 4
      local bullet = {
        owner = 99, px = 320 + lx - span, py = 180 + ly, x = 320 + lx + span, y = 180 + ly,
      }
      return Combat.bulletHitsPlane(bullet, p, sim.w, sim.h)
    end

    assert(shootAt(17, 0) == "guns", "nose should be guns")
    assert(shootAt(-13, 0) == "tail", "tail should be tail")
    assert(shootAt(-8, 4, 1) == "wing", "wing tip should be wing")
    assert(shootAt(0, 0) == "engine", "body should be engine")
    assert(shootAt(0, 40) == nil, "miss should not hit")
  end,
}

cases[#cases + 1] = {
  name = "a close-range shot cannot spawn past its target",
  fn = function()
    local sim = newSim(21)
    local target = sim:addPlane({ id = 1, x = 316, y = 180, angle = 0, invuln = 0 })
    local shooter = sim:addPlane({ id = 2, x = 300, y = 180, angle = 0, invuln = 0 })
    assert(sim:tryFire(shooter, { fire = true }), "shooter did not fire")
    sim:step({}, C.TICK)
    assert(target.hp < target.maxHp, "muzzle offset skipped a close target")
  end,
}

cases[#cases + 1] = {
  name = "a swept shot catches a target between the endpoints",
  fn = function()
    local sim = newSim(22)
    local target = sim:addPlane({ id = 1, x = 320, y = 180, angle = 0, invuln = 0 })
    local bullet = {
      owner = 2, px = 295, py = 180, x = 345, y = 180,
      vx = 540, vy = 0,
    }
    local part = Combat.bulletHitsPlane(bullet, target, sim.w, sim.h)
    assert(part ~= nil, "fast segment skipped the hitbox")
  end,
}

cases[#cases + 1] = {
  name = "shot and hit events carry bullet ids",
  fn = function()
    local sim = newSim(28)
    local target = sim:addPlane({ id = 1, x = 320, y = 180, angle = 0, invuln = 0 })
    local shooter = sim:addPlane({ id = 2, x = 250, y = 180, angle = 0, invuln = 0 })
    sim:tryFire(shooter, { fire = true })
    local shot
    for _, e in ipairs(sim.events) do if e.type == "shot" then shot = e end end
    assert(shot and shot.id, "shot event has no bullet id")
    local bullet = sim.bullets[#sim.bullets]
    target.invuln = 0
    local hit
    for _ = 1, 40 do
      sim:step({}, C.TICK)
      for _, e in ipairs(sim.events) do if e.type == "hit" then hit = e end end
    end
    assert(hit and hit.bulletId == bullet.id, "hit event lost its bullet id")
  end,
}

cases[#cases + 1] = {
  name = "network aim follows the client's rendered nose",
  fn = function()
    local sim = newSim(27)
    local p = sim:addPlane({ id = 1, x = 320, y = 180, angle = 0, speed = 120 })
    assert(sim:tryFire(p, { fire = true, aim = 0.2 }))
    local b = sim.bullets[#sim.bullets]
    local angle = math.atan2(b.vy, b.vx)
    assert(math.abs(angle - 0.2) < 0.02, "network aim was ignored")
  end,
}

cases[#cases + 1] = {
  name = "relative sweep agrees with fine substep sampling",
  fn = function()
    local rng = require("shared.rng").new(77)
    local sim = newSim(26)
    local target = sim:addPlane({ id = 1, x = 320, y = 180, angle = 0, invuln = 0 })
    local mismatches = 0
    for _ = 1, 1000 do
      local x0 = 320 + rng:range(-80, 20)
      local y0 = 180 + rng:range(-30, 30)
      local x1 = 320 + rng:range(-20, 80)
      local y1 = 180 + rng:range(-30, 30)
      local tx0 = 320 + rng:range(-20, 20)
      local ty0 = 180 + rng:range(-20, 20)
      local tx1 = 320 + rng:range(-20, 20)
      local ty1 = 180 + rng:range(-20, 20)
      local bullet = { owner = 2, px = x0, py = y0, x = x1, y = y1 }
      target.x, target.y = tx1, ty1
      local swept = Combat.bulletHitsMovingPlane(bullet, target, tx0, ty0, 0, sim.w, sim.h)

      local sampled = false
      for i = 0, 200 do
        local k = i / 200
        local bx = x0 + (x1 - x0) * k
        local by = y0 + (y1 - y0) * k
        local px = bx - (tx0 + (tx1 - tx0) * k)
        local py = by - (ty0 + (ty1 - ty0) * k)
        local lx, ly = Combat.toLocal(target, px, py)
        for _, shape in ipairs(Combat.SHAPES) do
          local dx, dy = lx - shape.x, ly - shape.y
          if dx * dx + dy * dy <= (shape.r + (bullet.radius or 0)) ^ 2 then
            sampled = true
          end
        end
      end
      if (swept ~= nil) ~= sampled then mismatches = mismatches + 1 end
    end
    assert(mismatches == 0, "sweep/substep disagreements: " .. mismatches)
  end,
}

cases[#cases + 1] = {
  name = "lag compensation checks the shooter's delayed target pose",
  fn = function()
    local sim = newSim(25)
    local target = sim:addPlane({ id = 1, x = 500, y = 100, angle = 0, invuln = 0 })
    local shooter = sim:addPlane({ id = 2, x = 200, y = 180, angle = 0, invuln = 0 })
    sim.time = 1.0
    target.history = {
      { t = 0.90, x = 320, y = 167, a = 0 },
      { t = 1.00, x = 360, y = 167, a = 0 },
    }
    sim.lagByOwner[2] = 0.10
    sim.bullets[1] = {
      owner = 2, team = 2, px = 300, py = 167, x = 340, y = 167,
      vx = 540, vy = 0, life = 1, damage = 8, radius = 1.8,
      firstStep = false, dead = false,
    }
    sim:step({ [1] = { throttle = 0.5 }, [2] = { throttle = 0.5 } }, C.TICK)
    assert(target.hp < target.maxHp, "delayed target pose was not checked")
    assert(shooter.alive)
  end,
}

cases[#cases + 1] = {
  name = "relative sweep catches a target and bullet crossing paths",
  fn = function()
    local sim = newSim(23)
    local target = sim:addPlane({ id = 1, x = 320, y = 200, angle = 0, invuln = 0 })
    local bullet = { owner = 2, px = 100, py = 160, x = 500, y = 160 }
    local part = Combat.bulletHitsMovingPlane(bullet, target, 320, 100, 0, sim.w, sim.h)
    assert(part ~= nil, "crossing relative paths missed")
  end,
}

cases[#cases + 1] = {
  name = "relative sweep does not hit a target that left the old pose",
  fn = function()
    local sim = newSim(24)
    local target = sim:addPlane({ id = 1, x = 320, y = 200, angle = 0, invuln = 0 })
    -- The bullet line crosses y=100 (the target's old position) but by the
    -- time the bullet reaches x=320 the target has moved to y=200. Absolute
    -- past-pose testing would incorrectly register this.
    local bullet = { owner = 2, px = 100, py = 100, x = 500, y = 100 }
    local part = Combat.bulletHitsMovingPlane(bullet, target, 320, 100, 0, sim.w, sim.h)
    assert(part == nil, "relative sweep hit a past pose")
  end,
}

cases[#cases + 1] = {
  name = "round start removes preparation invulnerability",
  fn = function()
    local Match = require("server.match")
    local m = Match.new({ { id = 1, name = "A" }, { id = 2, name = "B" } }, 44)
    assert(m.sim:getPlane(1).invuln > 0)
    m:beginRound()
    assert(m.sim:getPlane(1).invuln == 0, "spawn protection survived round start")
    assert(m.sim:getPlane(2).invuln == 0, "spawn protection survived round start")
  end,
}

cases[#cases + 1] = {
  name = "near-vertical crossfade tests both mirrored hitboxes",
  fn = function()
    local sim = newSim(24)
    local p = sim:addPlane({
      id = 1, x = 400, y = 225, angle = math.pi * 0.5 - 0.01,
      speed = 120, invuln = 0,
    })
    -- Mirrored local wing tip (-8, +4) at this angle.
    local wx, wy = p.x + 4, p.y - 8
    local b = { owner = 2, px = wx - 1, py = wy, x = wx + 1, y = wy }
    local part = Combat.bulletHitsPlane(b, p, sim.w, sim.h)
    assert(part ~= nil, "vertical mirrored wing was a phantom")
  end,
}

cases[#cases + 1] = {
  name = "bullets damage and kill",
  fn = function()
    local sim = newSim(8)
    local target = sim:addPlane({ id = 1, x = 320, y = 180, angle = 0, invuln = 0 })
    local shooter = sim:addPlane({ id = 2, x = 260, y = 180, angle = 0, invuln = 0 })

    for _ = 1, 20 do
      shooter.fireTimer = 0
      sim:tryFire(shooter, { fire = true })
      for _ = 1, 12 do sim:step({}, C.TICK) end
      target.invuln = 0
    end
    assert(target.hp < target.maxHp, "target took no damage")
  end,
}

cases[#cases + 1] = {
  name = "cloud visibility blocks line of sight",
  fn = function()
    local Clouds = require("shared.clouds")
    local clouds = Clouds.new(1, 3)
    -- Force a known puff.
    clouds.list = { { x = 100, y = 100, speed = 0, puffs = { { dx = 0, dy = 0, r = 30 } } } }
    assert(Clouds.pointInside(clouds, 100, 100))
    assert(Clouds.segmentBlocked(clouds, 20, 100, 180, 100))
    assert(not Clouds.segmentBlocked(clouds, 20, 200, 180, 200))
  end,
}

cases[#cases + 1] = {
  name = "AI recovers from a stall",
  fn = function()
    local AI = require("shared.ai")
    local sim = newSim(9)
    local p = sim:addPlane({ id = 1, x = 200, y = 100, angle = -1.4, speed = 50, throttle = 0 })
    local target = sim:addPlane({ id = 2, x = 500, y = 250, angle = 0, speed = 170 })
    local state = AI.newState()
    for _ = 1, 300 do
      local input = AI.input(p, target, sim, state, C.TICK)
      sim:step({ [1] = input, [2] = { throttle = 0.6 } }, C.TICK)
    end
    assert(not p.stalling, "AI never recovered from stall")
    assert(Flight.speed(p) > 110, "AI is still slow")
  end,
}

cases[#cases + 1] = {
  name = "AI pulls up near the ground",
  fn = function()
    local AI = require("shared.ai")
    local sim = newSim(10)
    local p = sim:addPlane({
      id = 1, x = 300, y = C.WORLD.groundY - 55,
      angle = 0, speed = 130, throttle = 0.7,
    })
    local input = AI.input(p, nil, sim, AI.newState(), C.TICK)
    assert(input.pitch < 0, "AI did not pitch up near the ground")
    assert(input.throttle == 1, "AI did not apply power near the ground")

    local high = sim:addPlane({ id = 2, x = 300, y = 100, angle = 0, speed = 130, throttle = 0.7 })
    local patrolState = AI.newState()
    patrolState.patrolTimer = 0
    AI.input(high, nil, sim, patrolState, C.TICK)
    assert(patrolState.patrolY <= C.WORLD.groundY - 120, "AI patrol target is below the ground margin")

    local sky = sim:addPlane({ id = 3, x = 300, y = 42, angle = 0, speed = 130, throttle = 0.7 })
    local skyInput = AI.input(sky, nil, sim, AI.newState(), C.TICK)
    assert(skyInput.pitch > 0, "AI did not dive away from the sky ceiling")
  end,
}

cases[#cases + 1] = {
  name = "left-facing pitch signs are plane-relative",
  fn = function()
    local sim = newSim(13)
    local down = sim:addPlane({ id = 1, x = 300, y = 225, angle = math.pi, speed = 130, throttle = 0.7 })
    local up = sim:addPlane({ id = 2, x = 500, y = 225, angle = math.pi, speed = 130, throttle = 0.7 })
    for _ = 1, 30 do
      sim:step({
        [1] = { throttle = 0.7, pitch = -1 },
        [2] = { throttle = 0.7, pitch = 1 },
      }, C.TICK)
    end
    assert(math.sin(down.angle) > 0.1, "negative pitch should lower the left-facing nose")
    assert(down.vy > 0, "negative pitch should produce downward velocity")
    assert(math.sin(up.angle) < -0.1, "positive pitch should raise the left-facing nose")
    assert(up.vy < 0, "positive pitch should produce upward velocity")
  end,
}

cases[#cases + 1] = {
  name = "pitch controls turn the plane",
  fn = function()
    local sim = newSim(12)
    local p = sim:addPlane({ id = 1, x = 320, y = 180, angle = 0, speed = 200 })
    for _ = 1, 30 do sim:step({ [1] = { throttle = 0.7, pitch = -1 } }, C.TICK) end
    assert(p.angle < -0.3, "up pitch did not rotate nose up: " .. p.angle)
    assert(math.abs(p.x - 320) > 5 or math.abs(p.y - 180) > 5, "plane did not move")
  end,
}

cases[#cases + 1] = {
  name = "ram damage has a cooldown",
  fn = function()
    local sim = newSim(13)
    local p1 = sim:addPlane({ id = 1, x = 320, y = 180, angle = 0, speed = 200 })
    local p2 = sim:addPlane({ id = 2, x = 320, y = 180, angle = 0, speed = 200 })
    p1.invuln, p2.invuln = 0, 0
    local hp1, hp2 = p1.hp, p2.hp
    sim:step({}, C.TICK)
    assert(p1.hp < hp1 and p2.hp < hp2, "initial ram did no damage")
    local after1, after2 = p1.hp, p2.hp
    for _ = 1, 20 do sim:step({}, C.TICK) end
    assert(p1.hp == after1 and p2.hp == after2, "ram damage repeated every tick")
  end,
}

cases[#cases + 1] = {
  name = "ramming emits kill events",
  fn = function()
    local sim = newSim(13)
    local p1 = sim:addPlane({ id = 1, x = 320, y = 180, angle = 0, speed = 200, hp = 10 })
    local p2 = sim:addPlane({ id = 2, x = 320, y = 180, angle = 0, speed = 200, hp = 10 })
    p1.invuln, p2.invuln = 0, 0
    local kills = 0
    for _, e in ipairs(sim:step({}, C.TICK)) do
      if e.type == "kill" then kills = kills + 1 end
    end
    assert(not p1.alive and not p2.alive, "ram should kill both low-health planes")
    assert(kills == 2, "ram kills did not emit kill events: " .. kills)
  end,
}

cases[#cases + 1] = {
  name = "spawn points are never cloud-hidden",
  fn = function()
    local Clouds = require("shared.clouds")
    for seed = 1, 50 do
      local clouds = Clouds.new(seed, 8)
      Clouds.avoidPoints(clouds, C.SPAWNS, 80)
      for _, spawn in ipairs(C.SPAWNS) do
        assert(not Clouds.pointInside(clouds, spawn.x, spawn.y),
          "spawn covered by cloud at seed " .. seed)
      end
    end
  end,
}

cases[#cases + 1] = {
  name = "touching the ground crashes the plane",
  fn = function()
    local sim = newSim(14)
    local p = sim:addPlane({
      id = 1, x = 400, y = C.WORLD.groundY - C.PLANE.radius - 1,
      angle = math.pi / 2, speed = 100, throttle = 0.7,
    })
    local crash = false
    for _, e in ipairs(sim:step({ [1] = { throttle = 0.7, pitch = 0 } }, C.TICK)) do
      if e.type == "crash" and e.victim == p.id then crash = true end
    end
    assert(not p.alive, "ground contact did not crash the plane")
    assert(crash, "ground crash event missing")
  end,
}

cases[#cases + 1] = {
  name = "gun heat jams and recovers",
  fn = function()
    local sim = newSim(15)
    local p = sim:addPlane({ id = 1, x = 400, y = 225, angle = 0, speed = 130, throttle = 0.7 })
    local overheat = false
    for _ = 1, 20 do
      p.fireTimer = 0
      sim:tryFire(p, { fire = true })
      for _, e in ipairs(sim.events) do
        if e.type == "overheat" and e.player == 1 then overheat = true end
      end
    end
    assert(overheat, "overheat event missing")
    assert((p.jammed or 0) > 0, "guns did not jam")
    assert(not Flight.canFire(p), "jammed guns can still fire")
    for _ = 1, 200 do sim:step({ [1] = { throttle = 0.7, pitch = 0, fire = false } }, C.TICK) end
    assert((p.jammed or 0) == 0 and p.heat < 1, "guns did not recover")
    assert(Flight.canFire(p), "guns did not become fireable again")
  end,
}

cases[#cases + 1] = {
  name = "camera clamps smoothly to the walled world",
  fn = function()
    local Camera = require("src.game.camera")
    local cam = Camera.new()
    Camera.follow(cam, 500, 260, 1)
    assert(cam.x >= 0 and cam.x <= C.WORLD.w - C.WORLD.viewW, "camera x outside world")
    assert(cam.y >= 0 and cam.y <= C.WORLD.h - C.WORLD.viewH, "camera y outside world")
    Camera.follow(cam, 0, 0, 1)
    assert(math.abs(cam.x) < 0.5 and math.abs(cam.y) < 0.5, "camera did not clamp at the left/top edge")
    Camera.follow(cam, C.WORLD.w, C.WORLD.h, 1)
    assert(math.abs(cam.x - (C.WORLD.w - C.WORLD.viewW)) < 0.5, "camera did not clamp at the right edge")
    assert(math.abs(cam.y - (C.WORLD.h - C.WORLD.viewH)) < 0.5, "camera did not clamp at the bottom edge")
  end,
}

cases[#cases + 1] = {
  name = "vision sectors and cloud line of sight",
  fn = function()
    local Vision = require("shared.vision")
    local Clouds = require("shared.clouds")
    local clouds = Clouds.new(77, 0)
    clouds.list = {}
    local viewer = { x = 400, y = 225, angle = 0, alive = true }
    assert(Vision.canSee(viewer, { x = 800, y = 225, alive = true }, clouds), "front target hidden")
    assert(not Vision.canSee(viewer, { x = 100, y = 225, alive = true }, clouds), "far rear target visible")
    assert(Vision.canSee(viewer, { x = 320, y = 225, alive = true }, clouds), "near rear target hidden")

    clouds.list = {
      { x = 550, y = 225, speed = 0, puffs = { { dx = 0, dy = 0, r = 40 } } },
    }
    assert(not Vision.canSee(viewer, { x = 800, y = 225, alive = true }, clouds),
      "cloud did not block forward vision")
    assert(not Vision.lineOfSight(viewer, { x = 650, y = 225 }, clouds),
      "cloud did not block line of sight")
  end,
}

cases[#cases + 1] = {
  name = "firing reveal respects range and line of sight",
  fn = function()
    local Vision = require("shared.vision")
    local Clouds = require("shared.clouds")
    local clouds = Clouds.new(78, 0)
    clouds.list = {}
    local viewer = { x = 300, y = 225, angle = 0, alive = true }
    assert(Vision.lineOfSight(viewer, { x = 700, y = 225 }, clouds), "clear shot line missing")
    clouds.list = {
      { x = 500, y = 225, speed = 0, puffs = { { dx = 0, dy = 0, r = 50 } } },
    }
    assert(not Vision.lineOfSight(viewer, { x = 700, y = 225 }, clouds), "cloud did not hide firing")
  end,
}

cases[#cases + 1] = {
  name = "clouds stay inside the walled arena",
  fn = function()
    local Clouds = require("shared.clouds")
    local clouds = Clouds.new(79, 0)
    clouds.list = {
      { x = 990, y = 100, speed = 0, puffs = { { dx = 0, dy = 0, r = 30 } } },
    }
    assert(Clouds.pointInside(clouds, 990, 100), "cloud is missing at its real position")
    assert(not Clouds.pointInside(clouds, 50, 100), "cloud wrapped to the far side of the map")
    assert(not Clouds.segmentBlocked(clouds, 20, 100, 80, 100),
      "cloud blocked a line on the far side of the map")
  end,
}

cases[#cases + 1] = {
  name = "stall severity is progressive with airspeed",
  fn = function()
    local sim = newSim(24)
    local medium = sim:addPlane({ id = 1, x = 300, y = 225, angle = 0, speed = 60, throttle = 0 })
    sim:step({ [1] = { throttle = 0, pitch = 0 } }, C.TICK)
    assert(medium.stallSeverity > 0 and medium.stallSeverity < 1,
      "medium-speed stall should be partial")

    local low = sim:addPlane({ id = 2, x = 500, y = 225, angle = 0, speed = 25, throttle = 0 })
    sim:step({ [2] = { throttle = 0, pitch = 0 } }, C.TICK)
    assert(low.stallSeverity > medium.stallSeverity,
      "lower airspeed should increase stall severity")

    local fast = sim:addPlane({ id = 3, x = 700, y = 225, angle = 0, speed = 160, throttle = 1 })
    for _ = 1, 10 do sim:step({ [3] = { throttle = 1, pitch = -1 } }, C.TICK) end
    assert(not fast.stalling, "high-speed pull should not immediately stall")
  end,
}

cases[#cases + 1] = {
  name = "aircraft registry drives shared flight stats",
  fn = function()
    local Aircraft = require("shared.aircraft")
    local Flight = require("shared.flight")
    assert(Aircraft.get("bf109e").id == "bf109e")
    assert(Aircraft.get("missing").id == "ik3")
    local a = Flight.new({ planeType = "bf109e" })
    assert(a.planeType == "bf109e")
    assert(a.ammo == 70)
    assert(a.parts.wing == 56)
    assert(a.spec.stats.maxSpeed == 188)
    local b = Flight.new({ planeType = "ik3" })
    assert(b.ammo == 90 and b.spec.stats.maxSpeed == 170)
  end,
}

cases[#cases + 1] = {
  name = "demo cloud cover forms wide shallow banks",
  fn = function()
    local Clouds = require("shared.clouds")
    local clouds = Clouds.new(91, C.CLOUDS.demoCount)
    local groups, loose, big = {}, 0, 0
    for _, c in ipairs(clouds.list) do
      if not c.cluster then loose = loose + 1 end
      if c.big then big = big + 1; assert(c.r >= 60, "big cloud is not big") end
      if c.cluster then
        groups[c.cluster] = groups[c.cluster] or { minY = 1e9, maxY = -1e9, n = 0, xs = {} }
        local g = groups[c.cluster]
        g.minY = math.min(g.minY, c.y)
        g.maxY = math.max(g.maxY, c.y)
        g.n = g.n + 1
        g.xs[#g.xs + 1] = c.x
      end
    end
    local count = 0
    for _, g in pairs(groups) do
      count = count + 1
      assert(g.n >= 3 and g.n <= 6, "demo cloud bank width outside 3-6")
      assert(g.maxY - g.minY <= 40, "demo cloud bank is not shallow")
      table.sort(g.xs)
      for i = 2, #g.xs do
        assert(g.xs[i] - g.xs[i - 1] >= 24, "clouds stacked within a bank")
      end
    end
    assert(count == 6, "demo clouds need six banks")
    assert(loose == 2, "demo should have two random singleton clouds")
    assert(big == 1, "demo should have exactly one big cloud")
  end,
}

cases[#cases + 1] = {
  name = "clouds never settle on the ground",
  fn = function()
    local Clouds = require("shared.clouds")
    for seed = 1, 40 do
      for _, count in ipairs({ C.CLOUDS.count, C.CLOUDS.demoCount }) do
        local clouds = Clouds.new(seed, count)
        Clouds.avoidPoints(clouds, C.SPAWNS, 80)
        for _, cloud in ipairs(clouds.list) do
          for _, puff in ipairs(cloud.puffs) do
            local bottom = cloud.y + (puff.dy or 0) + (puff.ry or puff.r)
            assert(bottom < C.WORLD.groundY,
              "cloud touches the ground at seed " .. seed)
          end
        end
      end
    end
  end,
}

cases[#cases + 1] = {
  name = "demo cloud wake emits entry and exit wisps",
  fn = function()
    local Clouds = require("shared.clouds")
    local CloudFx = require("src.game.cloudfx")
    local Particles = require("src.game.particles")
    local clouds = Clouds.new(92, C.CLOUDS.demoCount)
    local cloud = clouds.list[1]
    local particles = Particles.new(200)
    local fx = CloudFx.new()
    local plane = { x = cloud.x, y = cloud.y, vx = 130, vy = -20, alive = true }
    fx:update(C.TICK, plane, clouds, particles, true)
    assert(particles:count() >= 3, "no cloud entry wisps")
    assert((cloud.fxPulse or 0) > 0, "cloud did not pulse on entry")
    assert(#fx.wake.points > 0, "no cloud wake ribbon points")
    for _ = 1, 8 do
      plane.x = plane.x + 2
      fx:update(0.02, plane, clouds, particles, true)
    end
    fx:drawWake()
    local before = particles:count()
    plane.x, plane.y = 10, 10
    fx:update(C.TICK, plane, clouds, particles, true)
    assert(particles:count() > before, "no cloud exit scatter")
  end,
}

cases[#cases + 1] = {
  name = "cloud wake is left behind the aircraft",
  fn = function()
    local Clouds = require("shared.clouds")
    local CloudFx = require("src.game.cloudfx")
    local Particles = require("src.game.particles")
    local clouds = Clouds.new(93, C.CLOUDS.demoCount)
    local cloud = clouds.list[1]
    local particles = Particles.new(200)
    local fx = CloudFx.new()
    local plane = { x = cloud.x, y = cloud.y, vx = 150, vy = 0, alive = true }
    for _ = 1, 4 do fx:update(0.04, plane, clouds, particles, true) end
    plane.x = cloud.x + 140
    fx:update(0.04, plane, clouds, particles, true)
    local checked = 0
    for _, p in ipairs(particles.items) do
      if p.kind == "cloud" then
        checked = checked + 1
        assert(p.x <= plane.x, "cloud puff spawned ahead of the aircraft")
      end
    end
    assert(checked > 0, "no wake puffs")
  end,
}

cases[#cases + 1] = {
  name = "damage debris falls and fades",
  fn = function()
    local Particles = require("src.game.particles")
    local p = Particles.new(10)
    p:debris(100, 100, 30, 0, 2, 0.5, { 0.4, 0.4, 0.35 })
    local y = p.items[1].y
    for _ = 1, 10 do p:update(0.016) end
    assert(p.items[1] and p.items[1].kind == "debris")
    assert(p.items[1].y > y, "debris did not fall")
  end,
}

cases[#cases + 1] = {
  name = "network match scene loads",
  fn = function()
    local ok, err = pcall(require, "src.scenes.netmatch")
    assert(ok, tostring(err))
  end,
}

cases[#cases + 1] = {
  name = "detached aircraft panels fall and fade",
  fn = function()
    local Particles = require("src.game.particles")
    local PlaneArt = require("src.game.planeart")
    local art = PlaneArt.getArt("ik3")
    local p = Particles.new(10)
    p:panel(100, 100, 30, -20, art.wing, { 0.36, 0.42, 0.25 }, 1.0, 0, 1)
    local y = p.items[1].y
    for _ = 1, 12 do p:update(0.016) end
    assert(p.items[1] and p.items[1].kind == "panel")
    assert(p.items[1].y > y, "panel did not fall")
    p:drawPanels()
  end,
}

cases[#cases + 1] = {
  name = "lost wing and tail stop presenting hitboxes",
  fn = function()
    local Combat = require("shared.combat")
    local plane = { parts = { wing = 60, tail = 60, guns = 60 } }
    local full = #Combat.shapesFor(plane)
    plane.parts.wing = 20
    local noWing = #Combat.shapesFor(plane)
    assert(noWing < full, "destroyed wing did not remove a hitbox")
    plane.parts.tail = 20
    local noTail = #Combat.shapesFor(plane)
    assert(noTail < noWing, "destroyed tail did not remove a hitbox")
    plane.parts.guns = 10
    assert(#Combat.shapesFor(plane) < noTail, "destroyed guns did not remove a hitbox")
  end,
}

cases[#cases + 1] = {
  name = "death smoke hides and blinds for its lifetime",
  fn = function()
    local Sim = require("shared.sim")
    local Clouds = require("shared.clouds")
    local Vision = require("shared.vision")
    local sim = Sim.new({ seed = 7 })
    local before = #sim.clouds.list
    local smoke = sim:addSmokeCloud(500, 220, 1)
    assert(#sim.clouds.list == before + 1)
    assert(Clouds.pointInside(sim.clouds, 500, 220), "smoke has no blocking volume")
    local viewer = { x = 400, y = 220, angle = 0, alive = true }
    local target = { x = 620, y = 220, alive = true }
    assert(not Vision.canSee(viewer, target, sim.clouds), "smoke did not blind")
    Clouds.update(sim.clouds, smoke.maxLife + 0.1)
    assert(not Clouds.pointInside(sim.clouds, 500, 220), "smoke outlived its timer")
  end,
}

cases[#cases + 1] = {
  name = "match highlight recorder keeps a hit window",
  fn = function()
    local N = require("src.scenes.netmatch")
    local s = setmetatable({
      uiTime = 0, replayBuffer = {}, replayHits = {}, replayEvents = {},
      bestReplay = nil, bestReplayScore = 0, clouds = { list = {} },
    }, { __index = N })
    for i = 1, 30 do
      s.uiTime = i * 0.05
      s:recordReplayFrame({ planes = { { id = 1, x = 100, y = 100, a = 0, alive = true, team = 1 } }, bullets = {} })
    end
    s:noteHighlightHit({ damage = 12 })
    assert(s.bestReplay and #s.bestReplay > 0, "no best replay captured")
  end,
}

return cases
