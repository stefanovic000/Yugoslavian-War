-- Fixed 640x360 pixel viewport. All gameplay/UI coordinates live in this
-- virtual space; the canvas is scaled with nearest-neighbour filtering and
-- letterboxed. Physics never sees the window size.

local View = {
  W = 640,
  H = 360,
  scale = 2,
  ox = 0,
  oy = 0,
  canvas = nil,
}

function View.init()
  View.canvas = love.graphics.newCanvas(View.W, View.H)
  View.canvas:setFilter("nearest", "nearest")
  View.canvas:setWrap("clamp", "clamp")
  View.resize(love.graphics.getDimensions())
end

function View.resize(w, h)
  local s = math.min(w / View.W, h / View.H)
  if s >= 2 then
    s = math.floor(s)
  end
  if s < 0.5 then s = 0.5 end
  View.scale = s
  View.ox = math.floor((w - View.W * s) * 0.5)
  View.oy = math.floor((h - View.H * s) * 0.5)
end

function View.begin()
  love.graphics.push("all")
  love.graphics.setCanvas(View.canvas)
  love.graphics.clear(0, 0, 0, 1)
  love.graphics.origin()
  love.graphics.setScissor()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.setBlendMode("alpha")
end

function View.finish()
  love.graphics.setCanvas()
  love.graphics.pop()

  love.graphics.clear(0.012, 0.016, 0.024, 1)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(View.canvas, View.ox, View.oy, 0, View.scale, View.scale)
end

function View.toVirtual(x, y)
  return (x - View.ox) / View.scale, (y - View.oy) / View.scale
end

function View.mouse()
  local mx, my = love.mouse.getPosition()
  return View.toVirtual(mx, my)
end

return View
