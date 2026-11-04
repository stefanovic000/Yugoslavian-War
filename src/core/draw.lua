-- draw.lua
-- Palette + immediate-mode drawing helpers. Everything takes plain tables so
-- colors can be declared once and reused by both the game and the debug tools.

local fonts = require("src.core.fonts")
local util = require("src.core.util")

local draw = {}

local C = {
  bgTop = { 0.031, 0.043, 0.070 },
  bgBottom = { 0.063, 0.094, 0.125 },
  panel = { 0.047, 0.062, 0.086, 0.94 },
  panelSolid = { 0.047, 0.062, 0.086, 1 },
  panelRaised = { 0.075, 0.098, 0.130, 0.97 },
  border = { 0.20, 0.28, 0.38, 1 },
  borderSoft = { 0.16, 0.22, 0.30, 1 },
  text = { 0.87, 0.92, 0.97, 1 },
  dim = { 0.47, 0.56, 0.66, 1 },
  faint = { 0.27, 0.34, 0.42, 1 },
  accent = { 0.18, 0.88, 0.82, 1 },
  accentDim = { 0.09, 0.42, 0.40, 1 },
  orange = { 1.00, 0.58, 0.24, 1 },
  red = { 1.00, 0.32, 0.36, 1 },
  green = { 0.45, 0.95, 0.55, 1 },
  yellow = { 1.00, 0.82, 0.28, 1 },
  purple = { 0.72, 0.55, 1.00, 1 },
  blue = { 0.35, 0.68, 1.00, 1 },
  white = { 1, 1, 1, 1 },
  black = { 0, 0, 0, 1 },
}

draw.C = C

function draw.set(color, alpha)
  local a = alpha
  if a == nil then a = color[4] or 1 end
  love.graphics.setColor(color[1], color[2], color[3], a)
end

function draw.rect(mode, x, y, w, h, color, radius, alpha)
  draw.set(color, alpha)
  if radius and radius > 0 then
    love.graphics.rectangle(mode, x, y, w, h, radius, radius)
  else
    love.graphics.rectangle(mode, x, y, w, h)
  end
end

function draw.line(x1, y1, x2, y2, color, width)
  draw.set(color)
  love.graphics.setLineWidth(width or 1)
  love.graphics.line(x1, y1, x2, y2)
end

function draw.panel(x, y, w, h, opts)
  opts = opts or {}
  local radius = opts.radius or 6

  if opts.shadow ~= false then
    draw.rect("fill", x + 3, y + 4, w, h, C.black, radius, 0.28)
  end
  draw.rect("fill", x, y, w, h, opts.color or C.panel, radius)
  draw.set(opts.borderColor or C.borderSoft, opts.borderAlpha)
  love.graphics.setLineWidth(opts.borderWidth or 1)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, radius, radius)

  if opts.title then
    draw.set(opts.titleColor or C.accent)
    love.graphics.setFont(opts.titleFont or fonts.ui(13))
    love.graphics.print(opts.title, x + 10, y + 6)
  end
end

function draw.text(text, x, y, opts)
  opts = opts or {}
  local font = opts.font or fonts.ui(14)
  love.graphics.setFont(font)
  draw.set(opts.color or C.text, opts.alpha)
  if opts.shadow then
    draw.set(C.black, (opts.alpha or 1) * 0.6)
    if opts.width then
      love.graphics.printf(text, x + 1, y + 1, opts.width, opts.align or "left")
    else
      love.graphics.print(text, x + 1, y + 1)
    end
    draw.set(opts.color or C.text, opts.alpha)
  end
  if opts.width then
    love.graphics.printf(text, x, y, opts.width, opts.align or "left")
  else
    love.graphics.print(text, x, y)
  end
end

function draw.textWidth(font, text)
  local old = love.graphics.getFont()
  love.graphics.setFont(font)
  local w = font:getWidth(text)
  love.graphics.setFont(old)
  return w
end

function draw.bar(x, y, w, h, frac, color, bg, opts)
  opts = opts or {}
  frac = util.clamp01(frac or 0)
  draw.rect("fill", x, y, w, h, bg or C.faint, opts.radius or 2, opts.bgAlpha)
  if frac > 0 then
    draw.rect("fill", x, y, w * frac, h, color or C.accent, opts.radius or 2, opts.alpha)
  end
  if opts.border then
    draw.set(C.border)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, opts.radius or 2, opts.radius or 2)
  end
end

function draw.circle(mode, x, y, r, color, segments, alpha)
  draw.set(color, alpha)
  love.graphics.circle(mode, x, y, r, segments or 24)
end

function draw.polygon(mode, points, color, alpha)
  draw.set(color, alpha)
  love.graphics.polygon(mode, points)
end

function draw.checkmark(x, y, size, color)
  draw.set(color)
  love.graphics.setLineWidth(2)
  love.graphics.line(x, y + size * 0.5, x + size * 0.35, y + size * 0.85, x + size, y)
end

-- Pick a readable color for a 0..1 fraction (green -> yellow -> red).
function draw.healthColor(frac)
  if frac > 0.6 then return C.green end
  if frac > 0.3 then return C.yellow end
  return C.red
end

return draw
