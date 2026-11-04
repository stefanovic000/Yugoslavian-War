-- debugdraw.lua
-- World-space debug geometry. Every helper is a no-op unless enabled, so game
-- code can call these unconditionally.

local fonts = require("src.core.fonts")
local draw = require("src.core.draw")

local dd = {
  enabled = false,
  lineWidth = 1.5,
}

local C = draw.C

local function active()
  return dd.enabled
end

function dd.circle(x, y, r, color, segments)
  if not active() then return end
  love.graphics.setColor(color[1], color[2], color[3], color[4] or 0.8)
  love.graphics.setLineWidth(dd.lineWidth)
  love.graphics.circle("line", x, y, r, segments or 20)
end

function dd.point(x, y, color, size)
  if not active() then return end
  love.graphics.setColor(color[1], color[2], color[3], color[4] or 0.9)
  love.graphics.circle("fill", x, y, size or 3, 10)
end

function dd.line(x1, y1, x2, y2, color, width)
  if not active() then return end
  love.graphics.setColor(color[1], color[2], color[3], color[4] or 0.8)
  love.graphics.setLineWidth(width or dd.lineWidth)
  love.graphics.line(x1, y1, x2, y2)
end

function dd.ray(x, y, angle, length, color, width)
  if not active() then return end
  dd.line(x, y, x + math.cos(angle) * length, y + math.sin(angle) * length, color, width)
end

function dd.vector(x, y, dx, dy, color, width)
  if not active() then return end
  dd.line(x, y, x + dx, y + dy, color, width)
  local angle = math.atan2(dy, dx)
  local head = 6
  dd.line(x + dx, y + dy,
    x + dx - math.cos(angle - 0.45) * head,
    y + dy - math.sin(angle - 0.45) * head, color, width)
  dd.line(x + dx, y + dy,
    x + dx - math.cos(angle + 0.45) * head,
    y + dy - math.sin(angle + 0.45) * head, color, width)
end

function dd.rect(mode, x, y, w, h, color, radius)
  if not active() then return end
  love.graphics.setColor(color[1], color[2], color[3], color[4] or 0.7)
  love.graphics.setLineWidth(dd.lineWidth)
  love.graphics.rectangle(mode or "line", x, y, w, h, radius or 0, radius or 0)
end

function dd.label(text, x, y, color)
  if not active() then return end
  love.graphics.setFont(fonts.mono(11))
  love.graphics.setColor(0, 0, 0, 0.7)
  love.graphics.print(text, x + 1, y + 1)
  love.graphics.setColor(color[1], color[2], color[3], color[4] or 1)
  love.graphics.print(text, x, y)
end

function dd.grid(x0, y0, x1, y1, step, color)
  if not active() then return end
  step = step or 200
  local points = {}
  for x = x0, x1, step do
    points[#points + 1] = x
    points[#points + 1] = y0
    points[#points + 1] = x
    points[#points + 1] = y1
  end
  for y = y0, y1, step do
    points[#points + 1] = x0
    points[#points + 1] = y
    points[#points + 1] = x1
    points[#points + 1] = y
  end
  love.graphics.setColor(color[1], color[2], color[3], color[4] or 0.18)
  love.graphics.setLineWidth(1)
  if #points >= 4 then
    love.graphics.line(points)
  end
end

function dd.crosshair(x, y, size, color)
  if not active() then return end
  dd.line(x - size, y, x + size, y, color, 1)
  dd.line(x, y - size, x, y + size, color, 1)
end

function dd.resetStyle()
  love.graphics.setLineWidth(1)
  love.graphics.setColor(1, 1, 1, 1)
end

return dd
