-- Tiny pixel UI toolkit used by the menu, settings, lobby and match HUD.

local fonts = require("src.core.fonts")

local UI = {}

UI.C = {
  ink = { 0.025, 0.035, 0.035, 1 },
  ink2 = { 0.055, 0.075, 0.068, 1 },
  ink3 = { 0.105, 0.130, 0.105, 1 },
  cream = { 0.906, 0.886, 0.760, 1 },
  cream2 = { 0.620, 0.650, 0.520, 1 },
  orange = { 0.880, 0.560, 0.235, 1 },
  orange2 = { 0.540, 0.320, 0.120, 1 },
  teal = { 0.290, 0.590, 0.520, 1 },
  sky = { 0.560, 0.740, 0.760, 1 },
  red = { 0.720, 0.255, 0.200, 1 },
  green = { 0.560, 0.700, 0.380, 1 },
  white = { 1, 1, 1, 1 },
}

local C = UI.C

function UI.set(color, alpha)
  love.graphics.setColor(color[1], color[2], color[3], alpha or color[4] or 1)
end

function UI.font(size, bold)
  return bold and fonts.bold(size) or fonts.ui(size)
end

function UI.panel(x, y, w, h, opts)
  opts = opts or {}
  UI.set(C.ink, 0.55)
  love.graphics.rectangle("fill", x + 2, y + 2, w, h)
  UI.set(opts.color or C.ink)
  love.graphics.rectangle("fill", x, y, w, h)
  UI.set(opts.border or C.cream2)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1)

  -- tiny corner ticks, cockpit-panel style
  UI.set(C.orange)
  love.graphics.line(x, y + 6, x, y)
  love.graphics.line(x, y, x + 6, y)
  love.graphics.line(x + w - 6, y, x + w, y)
  love.graphics.line(x + w, y, x + w, y + 6)
end

function UI.hit(mx, my, x, y, w, h)
  return mx >= x and mx <= x + w and my >= y and my <= y + h
end

function UI.button(x, y, w, h, label, opts)
  opts = opts or {}
  local hover = opts.hover and not opts.disabled
  local selected = opts.selected and not opts.disabled
  local disabled = opts.disabled

  UI.set(selected and { 0.145, 0.155, 0.105, 1 }
    or (hover and { 0.110, 0.130, 0.100, 1 } or C.ink2))
  love.graphics.rectangle("fill", x, y, w, h)

  UI.set(disabled and C.ink3 or (selected and C.orange or (hover and C.cream or C.ink3)))
  love.graphics.setLineWidth(selected and 2 or 1)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1)
  love.graphics.setLineWidth(1)

  if selected then
    UI.set(C.orange)
    love.graphics.rectangle("fill", x, y, 3, h)
  end

  local font = opts.font or UI.font(12, true)
  love.graphics.setFont(font)
  if disabled then
    UI.set(C.cream2, 0.45)
  else
    UI.set(selected and C.orange or (hover and C.cream or C.cream2))
  end
  local ty = y + math.floor((h - font:getHeight()) * 0.5) - 1
  love.graphics.printf(label, x, ty, w, "center")

  if opts.hint then
    love.graphics.setFont(UI.font(7))
    UI.set(C.cream2)
    love.graphics.printf(opts.hint, x + 4, y + h - 10, w - 8, "right")
  end
end

function UI.card(x, y, w, h, number, title, subtitle, selected, hover)
  UI.set(selected and { 0.135, 0.145, 0.100, 0.97 } or { 0.045, 0.060, 0.055, 0.95 })
  love.graphics.rectangle("fill", x, y, w, h)
  UI.set(selected and C.orange or (hover and C.cream or C.cream2))
  love.graphics.setLineWidth(selected and 2 or 1)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1)
  love.graphics.setLineWidth(1)

  if selected then
    UI.set(C.orange)
    love.graphics.rectangle("fill", x, y, 4, h)
  end

  love.graphics.setFont(UI.font(9, true))
  UI.set(C.orange2)
  love.graphics.print(number, x + 12, y + 9)

  love.graphics.setFont(UI.font(12, true))
  UI.set(selected and C.orange or C.cream)
  love.graphics.print(title, x + 12, y + 22)

  love.graphics.setFont(UI.font(7))
  UI.set(C.cream2)
  love.graphics.print(subtitle, x + 12, y + 48)
end

function UI.textField(x, y, w, h, label, value, focused, caret)
  love.graphics.setFont(UI.font(8))
  UI.set(C.cream2)
  love.graphics.print(label, x, y - 11)

  UI.set(C.ink2)
  love.graphics.rectangle("fill", x, y, w, h)
  UI.set(focused and C.orange or C.ink3)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1)

  local font = UI.font(10)
  love.graphics.setFont(font)
  UI.set(C.cream)
  local textX = x + 6
  local avail = w - 12
  local before = value:sub(1, (caret or #value + 1) - 1)
  local offset = math.max(0, font:getWidth(before) - avail + 10)
  love.graphics.setScissor(textX, y + 3, avail, h - 6)
  love.graphics.print(value, textX - offset, y + math.floor((h - font:getHeight()) * 0.5))
  love.graphics.setScissor()

  if focused then
    local cx = textX + font:getWidth(before) - offset
    UI.set(C.orange)
    love.graphics.rectangle("fill", cx, y + 5, 2, h - 10)
  end
end

function UI.title(text, y, size, opts)
  opts = opts or {}
  local font = UI.font(size or 32, true)
  love.graphics.setFont(font)
  UI.set(C.ink, 0.55)
  love.graphics.printf(text, 2, y + 3, 640, "center")
  UI.set(opts.color or C.cream)
  love.graphics.printf(text, 0, y, 640, "center")
end

function UI.small(text, x, y, color, align, width)
  local font = UI.font(8)
  love.graphics.setFont(font)
  UI.set(color or C.cream2)
  local w = width
  if not w then
    if align == "center" then
      w = 640
    else
      w = 640 - x - 8
    end
  end
  love.graphics.printf(text, x, y, w, align or "left")
end

function UI.screenDim(alpha)
  UI.set(C.ink, alpha or 0.7)
  love.graphics.rectangle("fill", 0, 0, 640, 360)
end

-- Thin gun-heat meter. `jam` greater than zero paints the bar red.
function UI.heat(x, y, w, h, value, jam)
  UI.set(C.ink3)
  love.graphics.rectangle("fill", x, y, w, h)
  local v = math.max(0, math.min(1, value or 0))
  local col = (jam or 0) > 0 and C.red or (v > 0.72 and C.red or (v > 0.45 and C.orange or C.teal))
  UI.set(col)
  love.graphics.rectangle("fill", x, y, w * v, h)
  UI.set(C.ink, 0.65)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1)
end

return UI
