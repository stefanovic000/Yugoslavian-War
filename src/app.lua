-- app.lua
-- Scene stack + application lifecycle. Scenes can be pushed/popped (menu,
-- browser, settings, match) without rewiring main.lua.

local log = require("src.core.log")
local profiler = require("src.core.profiler")
local Debug = require("src.core.debug")

local App = {
  ready = false,
  scenes = {},
  time = 0,
  version = "0.1.0",
  rootScene = "src.scenes.menu",
  accumulator = 0,
}

function App:init(opts)
  self.opts = opts or {}
  self.version = _G.DOGFIGHT and _G.DOGFIGHT.version or self.version

  local seed = self.opts.seed
  if not seed then
    seed = os.time() + math.floor(os.clock() * 1000)
  end
  love.math.setRandomSeed(seed)
  self.seed = seed
  Debug.seed = seed

  log.info("App init (seed=%s)", tostring(seed))
  self.ready = true
  self.smoke = self.opts.smoke
  self.smokeFrame = 0
  self.shot = self.opts.shot
  self.shotFrames = self.opts.frames or 50
  self.shotTaken = false
  self.quitFrames = 0

  if self.opts.scene then
    local ok, scene = pcall(require, "src.scenes." .. self.opts.scene)
    if not ok then
      error("unknown --scene '" .. self.opts.scene .. "': " .. tostring(scene), 0)
    end
    self:push(scene)
  elseif self.opts.smoke then
    self:push(require("src.scenes.solo"))
  else
    self:push(require(self.rootScene))
  end

  self.uiTest = self.opts.uitest
  self.uiTestFrame = 0
  self.uiQuit = 0
end

function App:push(scene, ...)
  self.scenes[#self.scenes + 1] = scene
  self.accumulator = 0
  if scene.enter then
    scene:enter(...)
  end
  log.info("scene pushed: %s (depth %d)", tostring(scene.name or scene), #self.scenes)
end

function App:pop()
  local scene = table.remove(self.scenes)
  if scene and scene.leave then
    scene:leave()
  end
  if scene then
    log.info("scene popped: %s (depth %d)", tostring(scene.name or scene), #self.scenes)
  end
  return scene
end

function App:restart()
  local current = self.scenes[#self.scenes]
  if current and current.restartBlocked then
    log.warn("scene restart blocked: %s", tostring(current.name or current))
    return false
  end
  local target = (current and current.module) or self.rootScene

  while #self.scenes > 0 do
    self:pop()
  end

  for name in pairs(package.loaded) do
    if name:match("^src%.scenes%.") or name:match("^src%.entities%.") then
      package.loaded[name] = nil
    end
  end

  local ok, scene = pcall(require, target)
  if not ok then
    error("failed to reload scene '" .. target .. "': " .. tostring(scene), 0)
  end
  self:push(scene)
  log.info("scene reloaded from disk: %s", target)
  return true
end

function App:top()
  return self.scenes[#self.scenes]
end

function App:update(dt, realDt)
  self.time = self.time + dt
  local scene = self:top()

  if dt > 0 then
    self.accumulator = self.accumulator + dt
    local steps = 0
    while self.accumulator >= 1 / 60 and steps < 8 do
      if scene and scene.fixedUpdate then
        scene:fixedUpdate(1 / 60)
      end
      self.accumulator = self.accumulator - 1 / 60
      steps = steps + 1
    end

    if scene and scene.update then
      scene:update(dt)
    end
  end

  if self.smoke then
    self:updateSmoke(realDt or dt)
  end

  if self.shot then
    self.shotFrames = self.shotFrames - 1
    if self.shotFrames <= 0 then
      if not self.shotTaken then
        self.shotTaken = true
        Debug:screenshot(self.shot)
        self.quitFrames = 8
      elseif self.quitFrames > 0 then
        self.quitFrames = self.quitFrames - 1
        if self.quitFrames == 0 then
          print("SHOT OK  " .. tostring(self.shot))
          love.event.quit(0)
        end
      end
    end
  end

  if self.uiTest then
    self:updateUiTest()
  end
end

function App:updateUiTest()
  self.uiTestFrame = self.uiTestFrame + 1
  local f = self.uiTestFrame
  local View = require("src.game.view")

  local function click(vx, vy)
    love.mousepressed(View.ox + vx * View.scale, View.oy + vy * View.scale, 1, false, 1)
  end

  if f == 4 then
    click(545, 326) -- SETTINGS
  elseif f == 12 then
    click(150, 125) -- callsign field
  elseif f == 16 then
    for _ = 1, 8 do love.keypressed("backspace") end
  elseif f == 20 then
    love.textinput("ACE")
  elseif f == 24 then
    love.textinput("S")
  elseif f == 28 then
    love.keypressed("tab") -- server address field
  elseif f == 32 then
    love.textinput("192.168.1.50")
  elseif f == 38 then
    Debug:screenshot("preview-uitest")
    self.uiQuit = 8
  elseif f > 38 and self.uiQuit > 0 then
    self.uiQuit = self.uiQuit - 1
    if self.uiQuit == 0 then
      print("UITEST OK")
      love.event.quit(0)
    end
  end
end

function App:draw()
  profiler.push("draw")
  for i = 1, #self.scenes do
    local scene = self.scenes[i]
    if scene.draw then scene:draw() end
  end
  profiler.pop()
end

function App:keypressed(key, scancode, isrepeat)
  local scene = self:top()
  if scene and scene.keypressed then
    scene:keypressed(key, scancode, isrepeat)
  end
end

function App:keyreleased(key, scancode)
  local scene = self:top()
  if scene and scene.keyreleased then
    scene:keyreleased(key, scancode)
  end
end

function App:textinput(text)
  local scene = self:top()
  if scene and scene.textinput then
    scene:textinput(text)
  end
end

function App:mousepressed(x, y, button, istouch, presses)
  local scene = self:top()
  if scene and scene.mousepressed then
    scene:mousepressed(x, y, button, istouch, presses)
  end
end

function App:wheelmoved(x, y)
  local scene = self:top()
  if scene and scene.wheelmoved then
    scene:wheelmoved(x, y)
  end
end

function App:resize(w, h)
  local scene = self:top()
  if scene and scene.resize then
    scene:resize(w, h)
  end
end

function App:focus(focused)
  local scene = self:top()
  if scene and type(scene.focus) == "function" then
    scene:focus(focused)
  end
end

-------------------------------------------------------------------------------
-- unattended smoke run (used by smoke.bat / CI)
-------------------------------------------------------------------------------

function App:updateSmoke(dt)
  self.smokeFrame = self.smokeFrame + 1
  local f = self.smokeFrame

  local function cmd(line)
    Debug:runCommand(line)
  end

  if f == 5 then
    cmd("stats")
  elseif f == 8 then
    cmd("god")
  elseif f == 12 then
    cmd("ammo 120")
  elseif f == 16 then
    cmd("spawn")
  elseif f == 24 then
    Debug:screenshot("preview-solo")
  elseif f == 32 then
    Debug:setConsole(true)
  elseif f == 36 then
    cmd("help")
  elseif f == 44 then
    cmd("stats")
  elseif f == 50 then
    Debug:screenshot("preview-console")
  elseif f == 54 then
    Debug:setConsole(false)
  elseif f == 58 then
    cmd("pause")
  elseif f == 60 then
    cmd("step 2")
  elseif f == 62 then
    cmd("resume")
  elseif f == 66 then
    cmd("draw")
  elseif f == 68 then
    cmd("draw")
  elseif f == 72 then
    cmd("stats")
  elseif f == 76 then
    print("SMOKE OK  frames=" .. tostring(f) .. "  uptime=" .. string.format("%.2fs", Debug.uptime))
    love.event.quit(0)
  end
end

return App
