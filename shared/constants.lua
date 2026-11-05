-- Shared constants used by both the client and the dedicated server.
-- World units are the 800x450 arena; the client renders that arena at 0.8x
-- into the 640x360 pixel viewport. No gameplay value depends on window size,
-- aspect ratio or frame rate.

local C = {
  GAME_NAME = "Yugoslavian War",
  VERSION = "0.3.1",

  WORLD = {
    w = 1000, h = 520, scale = 0.8,
    viewW = 800, viewH = 450,
    groundY = 445, wallLeft = 40, wallRight = 960,
  },
  SPAWNS = {
    { x = 100, y = 140, angle = 0 },
    { x = 900, y = 380, angle = math.pi },
    { x = 100, y = 380, angle = 0 },
    { x = 900, y = 140, angle = math.pi },
  },
  SPAWNS3 = {
    { x = 100, y = 140, angle = 0 },
    { x = 900, y = 140, angle = math.pi },
    { x = 500, y = 390, angle = -math.pi / 2 },
  },
  TICK = 1 / 60,
  TICK_RATE = 60,
  SNAPSHOT_HZ = 20,

  MAX_PLAYERS = 4,
  MIN_PLAYERS = 2,
  ROUNDS = 6,
  ROUND_KILLS = 5,
  ROUND_BREAK = 3,
  PREP_TIME = 10,

  PLANE = {
    length = 34,
    radius = 10.0,
    hp = 120,
    partHp = 60,
    stallSpeed = 68,
    cruiseSpeed = 90,
    maxSpeed = 170,
    gravity = 100,
    thrust = 135,
    drag = 0.0031,
    engineBrake = 0.0018,
    slipDrag = 0.00018,
    turnDrag = 0.00015,
    climbLiftCut = 0.32,
    climbDrag = 0.0020,
    climbThrustCut = 0.50,
    pitchRate = 1.65,
    pitchDamping = 14,
    stallTorque = 0.85,
    stallAoa = 0.40,
    stallAoaSpeed = 110,
    stallLiftCut = 0.55,
    stallDrag = 0.0045,
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

  GUN = {
    heatPerShot = 0.095,
    coolRate = 0.34,
    jamTime = 2.5,
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
    demoCount = 26,
    minRadius = 22,
    maxRadius = 42,
    alpha = 0.88,
  },

  VISION = {
    near = 140,
    frontRange = 500,
    frontAngle = 70,
    sideRange = 320,
    sideAngle = 125,
    rearRange = 240,
    revealTime = 1.0,
    revealRange = 500,
  },
}

return C
