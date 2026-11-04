-- conf.lua
-- Window + module configuration. The console window is enabled by default on
-- Windows, except when VS Code's Local Lua Debugger is attached (it needs
-- stdio for its own protocol).

local function hasFlag(flag)
  for _, a in ipairs(arg or {}) do
    if a == "--" .. flag or a:sub(1, #flag + 3) == "--" .. flag .. "=" then
      return true
    end
  end
  return false
end

local debuggerAttached = os.getenv("LOCAL_LUA_DEBUGGER_VSCODE") == "1"
local isWindows = jit and jit.os == "Windows"
local serverMode = hasFlag("server")

function love.conf(t)
  t.identity = "dogfight"
  t.version = "11.5"
  t.console = isWindows and not debuggerAttached and not hasFlag("no-console")
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

