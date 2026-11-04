-- Hitboxes and projectile collision.
--
-- The plane is approximated by a small set of circles in local space. This is
-- cheap, stable, and easy to debug-render. Every circle is tagged with the
-- module it represents so hits damage a specific system.

local C = require("shared.constants")
local M = require("shared.mathx")

local Combat = {}

-- Local plane coordinates: +x is the nose, +y is down (screen coordinates).
local SHAPES = {
  { part = "guns",   x = 17,  y = 0,  r = 4.0 },
  { part = "guns",   x = 12,  y = -2, r = 3.4 },
  { part = "engine", x = 6,   y = 0,  r = 5.0 },
  { part = "engine", x = -3,  y = 0,  r = 5.0 },
  -- single low wing; the old upper-wing circle was left over from the
  -- symmetric pod and no longer matched the silhouette.
  { part = "wing",   x = -2,  y = 7,  r = 4.2 },
  { part = "wing",   x = -9,  y = 7,  r = 3.5 },
  { part = "tail",   x = -13, y = 0,  r = 4.2 },
  { part = "tail",   x = -16, y = -5, r = 3.2 },
}

Combat.SHAPES = SHAPES

-- The sprite is mirrored horizontally when flying left, not rotated upside
-- down. Hitboxes and effects must use the same transform or left-facing
-- planes get a vertically flipped wing/fin hitbox.
local function worldToLocal(angle, dx, dy)
  local ca, sa = math.cos(angle), math.sin(angle)
  if ca < 0 then
    return dx * ca + dy * sa, dx * sa - dy * ca
  end
  return dx * ca + dy * sa, -dx * sa + dy * ca
end

local function localToWorld(angle, x, y, lx, ly)
  local ca, sa = math.cos(angle), math.sin(angle)
  if ca < 0 then
    return x + ca * lx + sa * ly, y + sa * lx - ca * ly
  end
  return x + ca * lx - sa * ly, y + sa * lx + ca * ly
end

function Combat.toLocal(plane, dx, dy)
  return worldToLocal(plane.angle, dx, dy)
end

function Combat.toWorld(plane, lx, ly)
  return localToWorld(plane.angle, plane.x, plane.y, lx, ly)
end

local function segmentHitsCircle(x1, y1, x2, y2, cx, cy, r)
  return M.segmentPointDist2(cx, cy, x1, y1, x2, y2) <= r * r
end

-- Returns part, hitX, hitY if the bullet segment intersects this plane.
-- Tests wrapped copies so a plane straddling an edge still has a solid hitbox.
function Combat.bulletHitsPlane(bullet, plane, worldW, worldH)
  if not plane.alive or bullet.owner == plane.id then return nil end

  local w = worldW or C.WORLD.w
  local h = worldH or C.WORLD.h

  for _, ox in ipairs({ 0, -w, w }) do
    for _, oy in ipairs({ 0, -h, h }) do
      local cx = plane.x + ox
      local cy = plane.y + oy
      -- Cheap broad phase: bullet is nowhere near this copy.
      if math.abs(bullet.x - cx) < 40 and math.abs(bullet.y - cy) < 40 then
        local dx1, dy1 = bullet.px - cx, bullet.py - cy
        local dx2, dy2 = bullet.x - cx, bullet.y - cy
        local lx1, ly1 = worldToLocal(plane.angle, dx1, dy1)
        local lx2, ly2 = worldToLocal(plane.angle, dx2, dy2)

        for _, shape in ipairs(SHAPES) do
          if segmentHitsCircle(lx1, ly1, lx2, ly2, shape.x, shape.y, shape.r) then
            return shape.part, bullet.x, bullet.y
          end
        end
      end
    end
  end
  return nil
end

function Combat.pickupHitsPlane(pickup, plane, worldW, worldH)
  local w = worldW or C.WORLD.w
  local h = worldH or C.WORLD.h
  local d2 = M.wrappedDist2(pickup.x, pickup.y, plane.x, plane.y, w, h)
  local r = pickup.radius + plane.radius
  return d2 <= r * r
end

function Combat.planesRam(a, b, worldW, worldH)
  local w = worldW or C.WORLD.w
  local h = worldH or C.WORLD.h
  local d2 = M.wrappedDist2(a.x, a.y, b.x, b.y, w, h)
  local r = a.radius + b.radius
  return d2 <= r * r
end

-- Local hitbox shapes for the debug overlay.
function Combat.hitboxes(plane)
  return SHAPES, plane
end

return Combat
