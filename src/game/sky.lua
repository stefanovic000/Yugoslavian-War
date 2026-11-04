-- Dithered pixel sky. Generated once at 640x360 with an ordered Bayer
-- dither so it reads as hand-made pixel art instead of a smooth gradient.

local Sky = {}

local W, H = 640, 360
local BAYER = {
  { 0, 8, 2, 10 },
  { 12, 4, 14, 6 },
  { 3, 11, 1, 9 },
  { 15, 7, 13, 5 },
}

local PALETTE = {
  { 0.035, 0.070, 0.115 },
  { 0.070, 0.135, 0.190 },
  { 0.125, 0.225, 0.285 },
  { 0.235, 0.365, 0.405 },
  { 0.420, 0.505, 0.510 },
  { 0.640, 0.585, 0.505 },
  { 0.790, 0.625, 0.470 },
  { 0.850, 0.700, 0.520 },
}

local SUN = { 0.985, 0.900, 0.690 }
local STAR = { 0.700, 0.760, 0.740 }

local image

local function hash(x, y)
  local n = (x * 374761393 + y * 668265263) % 2147483647
  n = (n * 1274126177) % 2147483647
  return n / 2147483647
end

function Sky.init()
  if image then return end
  local data = love.image.newImageData(W, H)

  data:mapPixel(function(px, py)
    local x, y = px + 0.5, py + 0.5
    local t = y / H
    local pos = t * (#PALETTE - 1)
    local index = math.floor(pos)
    local frac = pos - index
    local c1 = PALETTE[math.min(index + 1, #PALETTE)]
    local c2 = PALETTE[math.min(index + 2, #PALETTE)]
    local threshold = (BAYER[(py % 4) + 1][(px % 4) + 1] + 0.5) / 16
    local c = (frac > threshold) and c2 or c1

    -- low sun, flat pixel disk with a few short rays
    local dx, dy = x - 512, y - 70
    local d = math.sqrt(dx * dx + dy * dy)
    if d < 12 then
      c = SUN
    elseif d > 15 and d < 23 then
      local ax, ay = math.abs(dx), math.abs(dy)
      if (ax < 1 and ay > 15) or (ay < 1 and ax > 15) then
        c = SUN
      elseif d < 20 and math.abs(ax - ay) < 1 then
        c = SUN
      end
    end

    -- a few hand-placed stars near the top
    if py < 72 and hash(px, py) < 0.0009 then
      c = STAR
    end

    return c[1], c[2], c[3], 1
  end)

  image = love.graphics.newImage(data)
  image:setFilter("nearest", "nearest")
end

function Sky.draw()
  Sky.init()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(image, 0, 0)
end

Sky.palette = PALETTE

return Sky
