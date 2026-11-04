-- Shared constants used by both the client and the dedicated server.
-- World units are the 800x450 arena; the client renders that arena at 0.8x
-- into the 640x360 pixel viewport. No gameplay value depends on window size,
-- aspect ratio or frame rate.

local C = {
  GAME_NAME = "Yugoslavian War",
  VERSION = "0.2.2",

  WORLD = { w = 800, h = 450, scale = 0.8, groundY = 365 },
  SPAWNS = {
    { x = 60, y = 120, angle = 0 },
    { x = 740, y = 330, angle = math.pi },
    { x = 60, y = 330, angle = 0 },
    { x = 740, y = 120, angle = math.pi },
  },
  TICK = 1 / 60,
  TICK_RATE = 60,
  SNAPSHOT_HZ = 20,

  MAX_PLAYERS = 4,
  MIN_PLAYERS = 2,
  ROUNDS = 5,
  ROUND_KILLS = 5,
  ROUND_BREAK = 3,
  PREP_TIME = 10,

  PLANE = {
    length = 34,
    radius = 10.5,
    hp = 120,
    partHp = 60,
    stallSpeed = 75,
    cruiseSpeed = 90,
    maxSpeed = 170,
    gravity = 100,
    thrust = 135,
    drag = 0.0031,
    engineBrake = 0.0018,
    slipDrag = 0.0002,
    turnDrag = 0.0002,
    climbLiftCut = 0.30,
    climbDrag = 0.0020,
    pitchRate = 1.3,
    stallTorque = 1.8,
    ammo = 90,
    maxAmmo = 120,
    fireInterval = 0.095,
    respawnTime = 3,
  },

  BULLET = {
    speed = 540,
    life = 1.15,
    damage = 8,
    radius = 1.8,
    spread = 0.008,
  },

  PICKUP = {
    ammo = 45,
    fallSpeed = 26,
    radius = 12,
    interval = 16,
    max = 3,
  },

  CLOUDS = {
    count = 8,
    minRadius = 22,
    maxRadius = 42,
    alpha = 0.88,
  },
}

return C
