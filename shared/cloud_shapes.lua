-- Shared cloud silhouette blobs. Rendering and visibility use the same ellipses,
-- so a shadow always starts at the cloud the player can actually see.

local Shapes = {}

local VARIANTS = {
  { { 30, 34, 18, 12 }, { 48, 28, 24, 16 }, { 66, 34, 16, 11 }, { 39, 23, 14, 10 } },
  { { 28, 32, 16, 11 }, { 45, 28, 22, 15 }, { 63, 33, 18, 12 }, { 78, 38, 9, 7 } },
  { { 34, 30, 20, 13 }, { 54, 32, 22, 14 }, { 70, 34, 13, 9 }, { 22, 38, 9, 7 } },
}

function Shapes.blobs(variant)
  return VARIANTS[variant] or VARIANTS[1]
end

-- Converts the 96x56 image-space blobs to world-space ellipses for one cloud.
function Shapes.puffs(variant, radius)
  local sx = radius * 2.0 / 96
  local sy = radius * 1.3 / 56
  local out = {}
  for i, b in ipairs(Shapes.blobs(variant)) do
    out[i] = {
      dx = (b[1] - 48) * sx,
      dy = (b[2] - 28) * sy,
      rx = b[3] * sx,
      ry = b[4] * sy,
      r = math.max(b[3] * sx, b[4] * sy),
    }
  end
  return out
end

return Shapes
