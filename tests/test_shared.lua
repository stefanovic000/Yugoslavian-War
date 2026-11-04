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
    -- Local wing is (-2, +7); at angle pi the mirrored sprite puts it at
    -- world (+2, +7). This is deliberately not computed with Combat.toWorld.
    local wx, wy = p.x + 2, p.y + 7
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

    local function shootAt(lx, ly)
      local bullet = {
        owner = 99, px = 320 + lx - 4, py = 180 + ly, x = 320 + lx + 4, y = 180 + ly,
      }
      return Combat.bulletHitsPlane(bullet, p, sim.w, sim.h)
    end

    assert(shootAt(17, 0) == "guns", "nose should be guns")
    assert(shootAt(-13, 0) == "tail", "tail should be tail")
    assert(shootAt(-2, 8) == "wing", "wing should be wing")
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

return cases
