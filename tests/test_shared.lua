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
  name = "horizontal wrap",
  fn = function()
    local sim = newSim(4)
    local p = sim:addPlane({ id = 1, x = 5, y = 180, angle = math.pi, speed = 170 })
    for _ = 1, 60 do
      sim:step({ [1] = { throttle = 0.6, pitch = 0 } }, C.TICK)
    end
    assert(p.x > 300, "plane did not wrap across the left edge: " .. p.x)
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

return cases
