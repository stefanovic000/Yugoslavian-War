-- main.lua
-- Boot sequence and LÖVE callbacks. The game renders into a fixed 640x360
-- pixel canvas; the debug toolkit draws at native window resolution on top.

local cli = require("src.core.cli")
local opts = cli.parse(arg)

_G.DOGFIGHT = { version = "0.2.3", opts = opts }

-- Dedicated server mode. Runs headless from the same checkout; the Ubuntu
-- deployment uses server/run.lua with LuaSocket instead.
if opts.server then
  local Server = require("server.server")
  local port = tonumber(opts.flags.port) or 7777
  local host = opts.flags.host or "0.0.0.0"
  function love.load()
    local server = Server.new({ port = port, host = host })
    server:run()
  end
  function love.draw() end
  function love.quit() end
  return
end

-- VS Code "Local Lua Debugger" support.
if os.getenv("LOCAL_LUA_DEBUGGER_VSCODE") == "1" then
  local ok, lld = pcall(require, "lldebugger")
  if ok and lld and lld.start then
    lld.start()
  else
    print("[debugger] LOCAL_LUA_DEBUGGER_VSCODE is set but lldebugger is unavailable: " .. tostring(lld))
  end
end

local log = require("src.core.log")
local Debug = require("src.core.debug")
local Errors = require("src.core.errors")
local profiler = require("src.core.profiler")
local Input = require("src.core.input")
local App = require("src.app")
local View = require("src.game.view")
local Settings = require("src.game.settings")

function love.load()
  love.graphics.setDefaultFilter("nearest", "nearest", 1)
  love.graphics.setLineStyle("rough")
  love.graphics.setBackgroundColor(0.012, 0.016, 0.024)
  love.graphics.setColor(1, 1, 1, 1)

  log.init(opts)
  Errors.install(opts)
  Debug:init(opts)
  Settings.load()
  Settings.apply()
  View.init()

  log.info("%s %s starting (love %s)", "Yugoslavian War", DOGFIGHT.version,
    table.concat({ love.getVersion() }, "."))
  log.info("arguments: %s", table.concat(arg or {}, " "))
  log.info("save directory: %s", tostring(love.filesystem.getSaveDirectory()))

  if opts.test then
    local Tests = require("tests.run")
    local ok = Tests.run()
    love.event.quit(ok and 0 or 1)
    return
  end

  if opts.crash then
    error("Intentional crash test (--crash)")
  end

  App:init(opts)
end

function love.update(dt)
  if not App.ready then return end
  dt = math.min(dt, 0.1)

  profiler.beginFrame()
  profiler.push("update")

  local gameDt = Debug:timeStep(dt)
  App:update(gameDt, dt)
  Debug:update(dt)
  Input.endFrame()

  profiler.pop()
end

function love.draw()
  if App.ready then
    View.begin()
    App:draw()
    View.finish()
    Debug:draw()
    profiler.finishFrame()
  end
end

function love.keypressed(key, scancode, isrepeat)
  local consumed = Debug:keypressed(key, scancode, isrepeat)
  Input.keypressed(key, isrepeat)
  if not consumed and not Debug.consoleOpen and App.ready then
    App:keypressed(key, scancode, isrepeat)
  end
end

function love.keyreleased(key, scancode)
  Input.keyreleased(key)
  if not Debug.consoleOpen and App.ready then
    App:keyreleased(key, scancode)
  end
end

function love.textinput(text)
  if Debug.consoleOpen then
    Debug:textinput(text)
  elseif App.ready then
    App:textinput(text)
  end
end

function love.mousepressed(x, y, button, istouch, presses)
  Input.mousepressed(button)
  if not Debug.consoleOpen and App.ready then
    App:mousepressed(x, y, button, istouch, presses)
  end
end

function love.mousereleased(x, y, button, istouch, presses)
  Input.mousereleased(button)
end

function love.wheelmoved(x, y)
  if Debug:wheelmoved(x, y) then return end
  if App.ready then
    App:wheelmoved(x, y)
  end
end

function love.focus(focused)
  if not focused then
    Input.reset()
  end
  if App.ready then
    App:focus(focused)
  end
end

function love.resize(w, h)
  View.resize(w, h)
  if App.ready then
    App:resize(w, h)
  end
end

function love.quit()
  log.info("quit")
  return false
end
