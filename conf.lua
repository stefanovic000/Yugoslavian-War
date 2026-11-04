-- conf.lua
-- Window + module configuration. Release builds never open a console window;
-- the in-game F2 console and file logging remain available.

local function hasFlag(flag)
  for _, a in ipairs(arg or {}) do
    if a == "--" .. flag or a:sub(1, #flag + 3) == "--" .. flag .. "=" then
      return true
    end
  end
  return false
end

local serverMode = hasFlag("server")

function love.conf(t)
  t.identity = "dogfight"
  t.version = "11.5"
  -- Release builds use the normal GUI executable; do not pop a console window.
  -- The in-game F2 developer console and file logging remain available.
  t.console = false
  t.accelerometerjoystick = false
  t.externalstorage = false
  t.gammacorrect = false

  t.window.title = "Yugoslavian War"
  t.window.icon = "assets/icon.png"
  t.window.width = 1280
  t.window.height = 720
  t.window.minwidth = 960
  t.window.minheight = 540
  t.window.resizable = true
  t.window.vsync = 1
  t.window.msaa = 0
  t.window.highdpi = false
  t.window.depth = false
  t.window.stencil = false

  t.modules.physics = false
  t.modules.video = false
  t.modules.touch = false
  t.modules.joystick = false
  t.modules.audio = true

  if serverMode then
    t.window = false
    t.modules.window = false
    t.modules.graphics = false
    t.modules.audio = false
    t.modules.image = false
  end
end

