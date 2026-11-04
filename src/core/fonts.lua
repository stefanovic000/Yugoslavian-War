-- fonts.lua
-- Central font cache. Uses the bundled Silkscreen pixel face for UI and Space
-- Mono for debug/console text, with LÖVE's built-in font as a fallback.

local fonts = {
  cache = {},
  paths = {
    ui = "assets/fonts/Silkscreen-Regular.ttf",
    bold = "assets/fonts/Silkscreen-Bold.ttf",
    mono = "assets/fonts/SpaceMono-Regular.ttf",
  },
}

local function exists(path)
  local ok, info = pcall(love.filesystem.getInfo, path)
  return ok and info ~= nil
end

local function create(path, size)
  if path and exists(path) then
    local ok, font = pcall(love.graphics.newFont, path, size)
    if ok and font then
      font:setFilter("nearest", "nearest")
      return font
    end
  end
  return love.graphics.newFont(size)
end

function fonts.get(kind, size)
  size = math.max(6, math.floor(size or 14))
  local key = kind .. ":" .. size
  local font = fonts.cache[key]
  if font then return font end

  font = create(fonts.paths[kind] or fonts.paths.ui, size)
  fonts.cache[key] = font
  return font
end

function fonts.ui(size) return fonts.get("ui", size) end
function fonts.bold(size) return fonts.get("bold", size) end
function fonts.mono(size) return fonts.get("mono", size) end

function fonts.clear()
  fonts.cache = {}
end

return fonts
