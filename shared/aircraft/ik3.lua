-- Rogožarski IK-3: the baseline turn fighter.
-- Keep this file data-only: shared flight/combat code must consume it.

return {
  id = "ik3",
  name = "Rogozarski IK-3",
  shortName = "IK-3",
  role = "Turn fighter",
  year = 1940,

  stats = {
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

  visual = {
    art = "ik3",
    scale = 0.95,
    palette = {
      body = { 0.36, 0.42, 0.25 },
      dark = { 0.17, 0.22, 0.13 },
      light = { 0.66, 0.72, 0.50 },
      accent = { 0.82, 0.70, 0.32 },
    },
    roundel = "yugoslav",
  },
}
