-- Messerschmitt Bf 109E: fast energy fighter with a weaker sustained turn.
-- Test aircraft for the modular aircraft registry.

return {
  id = "bf109e",
  name = "Messerschmitt Bf 109E",
  shortName = "BF 109E",
  role = "Energy fighter",
  year = 1939,

  stats = {
    length = 34,
    radius = 10.2,
    hp = 112,
    partHp = 56,
    stallSpeed = 71,
    cruiseSpeed = 96,
    maxSpeed = 188,
    gravity = 100,
    thrust = 150,
    drag = 0.0028,
    engineBrake = 0.0017,
    slipDrag = 0.00018,
    turnDrag = 0.00015,
    climbLiftCut = 0.34,
    climbDrag = 0.0021,
    climbThrustCut = 0.48,
    pitchRate = 1.46,
    pitchDamping = 14,
    stallTorque = 0.88,
    stallAoa = 0.39,
    stallAoaSpeed = 112,
    stallLiftCut = 0.57,
    stallDrag = 0.0047,
    ammo = 70,
    maxAmmo = 100,
    fireInterval = 0.105,
    respawnTime = 3,
  },

  visual = {
    art = "bf109e",
    scale = 0.96,
    palette = {
      body = { 0.48, 0.52, 0.50 },
      dark = { 0.22, 0.26, 0.27 },
      light = { 0.74, 0.77, 0.70 },
      accent = { 0.86, 0.70, 0.22 },
    },
    roundel = "balkan",
  },
}
