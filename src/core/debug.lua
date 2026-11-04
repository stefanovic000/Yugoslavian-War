-- debug.lua
-- The development cockpit: HUD, frame graph, live watches, profiler, and an
-- interactive console with commands, history and completion.
--
-- This module is deliberately independent from gameplay. Scenes register
-- commands and watches into a namespace and remove them again on leave.

local util = require("src.core.util")
local draw = require("src.core.draw")
local fonts = require("src.core.fonts")
local log = require("src.core.log")
local profiler = require("src.core.profiler")
local dd = require("src.core.debugdraw")

local C = draw.C

local Debug = {
  initialized = false,
  hudVisible = false,
  consoleOpen = false,
  drawEnabled = false,
  paused = false,
  timeScale = 1,
  stepFrames = 0,
  showProfiler = true,

  frameMs = 16.7,
  frameMsAvg = 16.7,
  frameMsPeak = 16.7,
  fps = 0,
  fpsAvg = 60,
  memMB = 0,
  drawCalls = 0,
  uptime = 0,
  seed = nil,

  graph = {},
  maxGraph = 180,

  commands = {},
  commandOrder = {},
  watches = {},
  watchOrder = {},

  lines = {},
  maxLines = 1200,
  history = {},
  historyIndex = 1,
  input = "",
  caret = 1,
  scroll = 0,

  toasts = {},
  _wrapDirty = true,
  _wrapped = {},
  _wrapWidth = 0,
}

local kindColors = {
  cmd = C.accent,
  info = C.text,
  dim = C.dim,
  ok = C.green,
  warn = C.yellow,
  error = C.red,
  log = C.dim,
}

-------------------------------------------------------------------------------
-- setup
-------------------------------------------------------------------------------

function Debug:init(opts)
  self.opts = opts or {}
  self.initialized = true
  self.bootTime = love.timer.getTime()
  self.frameMsAvg = 16.7
  self.seed = self.opts.seed

  self:registerCoreCommands()

  if self.opts.nohud then
    self.hudVisible = false
    self.showProfiler = false
    self.toasts = {}
  end

  log.onEntry = function(entry)
    if entry.level == "warn" then
      Debug:toast(entry.message, "warn")
    elseif entry.level == "error" or entry.level == "fatal" then
      Debug:toast(entry.message, "error", 6)
    end
  end

  self:echo("Yugoslavian War dev console ready. Type 'help' for commands.", "ok")
  log.info("debug overlay ready (F1 hud, F2 console, F3 debug draw)")
end

function Debug:registerCoreCommands()
  local D = self

  D:command("help", "List commands, or describe one", function(args)
    if args[1] then
      local cmd = D.commands[args[1]]
      if not cmd then
        D:echo("No command named '" .. args[1] .. "'.", "error")
        return
      end
      D:echo(cmd.name .. " - " .. cmd.desc, "info")
      if cmd.usage then D:echo("  usage: " .. cmd.usage, "dim") end
      return
    end

    local out = { "Commands:" }
    for _, name in ipairs(D.commandOrder) do
      local cmd = D.commands[name]
      out[#out + 1] = string.format("  %-12s %s", name, cmd.desc)
    end
    D:echo(table.concat(out, "\n"), "info")
  end, { usage = "help [command]" })

  D:command("clear", "Clear the console scrollback", function()
    D:clearConsole()
  end)

  D:command("echo", "Print text back", function(args)
    D:echo(table.concat(args, " "), "info")
  end, { usage = "echo <text>" })

  D:command("stats", "Print a one-shot runtime report", function()
    local gs = love.graphics.getStats()
    local App = D:getApp()
    local sceneCount = App and #App.scenes or 0
    D:echo(table.concat({
      string.format("fps=%d  frame=%.2fms  avg=%.2fms  peak=%.2fms", D.fps, D.frameMs, D.frameMsAvg, D.frameMsPeak),
      string.format("memory=%.1fMB  drawcalls=%d  canvases=%d  scenes=%d", D.memMB, D.drawCalls, gs.canvases or 0, sceneCount),
      string.format("state=%s  timescale=%.2f  paused=%s  console=%s", D:status(), D.timeScale, tostring(D.paused), tostring(D.consoleOpen)),
      string.format("seed=%s  uptime=%.1fs  save=%s", tostring(D.seed), D.uptime, tostring(log.saveDir)),
      "log=" .. tostring(log.path()),
    }, "\n"), "info")
  end)

  D:command("pause", "Pause gameplay updates", function()
    D.paused = true
    D:toast("Paused", "warn", 1.5)
  end)

  D:command("resume", "Resume gameplay updates", function()
    D.paused = false
    D:toast("Resumed", "ok", 1.5)
  end)

  D:command("step", "Advance the paused game by N frames", function(args)
    local n = math.max(1, math.floor(tonumber(args[1]) or 1))
    D.paused = true
    D.stepFrames = D.stepFrames + n
    D:echo(string.format("stepping %d frame(s)", n), "ok")
  end, { usage = "step [frames]" })

  D:command("timescale", "Set the game time multiplier (0-8)", function(args)
    local n = tonumber(args[1])
    if not n then D:echo("usage: timescale <number 0-8>", "error") return end
    D.timeScale = util.clamp(n, 0, 8)
    D:echo(string.format("timescale = %.2f", D.timeScale), "ok")
  end, { usage = "timescale <0-8>" })

  D:command("slowmo", "Toggle 0.25x slow motion", function()
    if D.timeScale == 0.25 then
      D.timeScale = 1
    else
      D.timeScale = 0.25
    end
    D:echo(string.format("timescale = %.2f", D.timeScale), "ok")
  end)

  D:command("restart", "Reload the current scene from disk", function()
    D:echo("restarting scene...", "warn")
    local ok = D:getApp():restart()
    if ok == false then D:echo("restart is blocked in a live match", "warn") end
  end)

  D:command("hud", "Toggle the debug HUD (F1)", function()
    D.hudVisible = not D.hudVisible
    D:echo("hud " .. (D.hudVisible and "on" or "off"), "ok")
  end)

  D:command("draw", "Toggle debug geometry (F3)", function()
    D:setDrawEnabled(not D.drawEnabled)
    D:echo("debug draw " .. (D.drawEnabled and "on" or "off"), "ok")
  end)

  D:command("profiler", "Toggle the profiler panel (F4)", function()
    D.showProfiler = not D.showProfiler
    D:echo("profiler " .. (D.showProfiler and "on" or "off"), "ok")
  end)

  D:command("watch", "List live watches", function()
    local list = D:watchList()
    if #list == 0 then
      D:echo("(no watches registered)", "dim")
      return
    end
    for _, item in ipairs(list) do
      D:echo(string.format("%-18s %s", item.name, item.value), "info")
    end
  end)

  D:command("log", "Set the log level", function(args)
    local level = args[1] or "debug"
    local ok, err = log.setLevel(level)
    if ok then
      D:echo("log level = " .. level, "ok")
    else
      D:echo(err, "error")
    end
  end, { usage = "log <trace|debug|info|warn|error|fatal|off>" })

  D:command("seed", "Show or set the RNG seed", function(args)
    if args[1] then
      local n = tonumber(args[1])
      if not n then D:echo("usage: seed <integer>", "error") return end
      love.math.setRandomSeed(math.floor(n))
      D.seed = math.floor(n)
      D:echo("random seed = " .. D.seed, "ok")
    else
      local seed = D.seed
      if not seed then
        local ok, current = pcall(love.math.getRandomSeed)
        seed = ok and current or "?"
      end
      D:echo("random seed = " .. tostring(seed), "info")
    end
  end, { usage = "seed [integer]" })

  D:command("screenshot", "Save a PNG to the LÖVE save directory", function(args)
    D:screenshot(args[1])
  end, { usage = "screenshot [filename.png]" })

  D:command("logs", "Open the log folder in Explorer", function()
    local url = "file:///" .. tostring(log.saveDir):gsub("\\", "/")
    local ok, err = pcall(love.system.openURL, url)
    if ok then
      D:echo("opened " .. url, "ok")
    else
      D:echo("could not open folder: " .. tostring(err), "error")
    end
  end)

  D:command("version", "Print engine and game versions", function()
    D:echo("YUGOSLAVIAN WAR " .. tostring(_G.DOGFIGHT and _G.DOGFIGHT.version or "dev"), "info")
    D:echo("LÖVE " .. table.concat({ love.getVersion() }, "."), "info")
    D:echo("LuaJIT " .. tostring(jit and jit.version or "?"), "dim")
  end)

  D:command("hide", "Close the console", function()
    D:setConsole(false)
  end)

  D:command("quit", "Quit the game", function()
    love.event.quit(0)
  end)
end

function Debug:command(name, desc, fn, opts)
  opts = opts or {}
  if not self.commands[name] then
    self.commandOrder[#self.commandOrder + 1] = name
  end
  self.commands[name] = {
    name = name,
    desc = desc,
    fn = fn,
    usage = opts.usage,
    ns = opts.ns,
  }
end

function Debug:removeCommands(ns)
  local kept = {}
  for _, name in ipairs(self.commandOrder) do
    local cmd = self.commands[name]
    if cmd and cmd.ns == ns then
      self.commands[name] = nil
    else
      kept[#kept + 1] = name
    end
  end
  self.commandOrder = kept
end

function Debug:watch(name, fn, ns)
  if not self.watches[name] then
    self.watchOrder[#self.watchOrder + 1] = name
  end
  self.watches[name] = { name = name, fn = fn, ns = ns }
end

function Debug:unwatch(name)
  if self.watches[name] then
    self.watches[name] = nil
    for i, n in ipairs(self.watchOrder) do
      if n == name then
        table.remove(self.watchOrder, i)
        break
      end
    end
  end
end

function Debug:clearWatches(ns)
  local kept = {}
  for _, name in ipairs(self.watchOrder) do
    local w = self.watches[name]
    if w and w.ns == ns then
      self.watches[name] = nil
    else
      kept[#kept + 1] = name
    end
  end
  self.watchOrder = kept
end

function Debug:formatValue(watch)
  local ok, value = pcall(watch.fn)
  if not ok then return "ERR", C.red end
  if type(value) == "number" then
    if value % 1 == 0 then return tostring(value), C.text end
    return string.format("%.1f", value), C.text
  elseif type(value) == "boolean" then
    return value and "on" or "off", value and C.green or C.dim
  elseif value == nil then
    return "-", C.dim
  end
  return tostring(value), C.text
end

function Debug:watchList()
  local list = {}
  for _, name in ipairs(self.watchOrder) do
    local watch = self.watches[name]
    if watch then
      local value, color = self:formatValue(watch)
      list[#list + 1] = { name = name, value = value, color = color, ns = watch.ns }
    end
  end
  return list
end

function Debug:getApp()
  local ok, App = pcall(require, "src.app")
  return ok and App or nil
end

-------------------------------------------------------------------------------
-- console
-------------------------------------------------------------------------------

function Debug:echo(text, kind)
  local s = tostring(text)
  for line in (s .. "\n"):gmatch("(.-)\n") do
    self.lines[#self.lines + 1] = { text = line, kind = kind or "info" }
  end
  if #self.lines > self.maxLines then
    local excess = #self.lines - self.maxLines
    for _ = 1, excess do table.remove(self.lines, 1) end
  end
  self._wrapDirty = true
  self.scroll = 0
  log.debug("[console] %s", s)
end

function Debug:clearConsole()
  self.lines = {}
  self.scroll = 0
  self._wrapDirty = true
end

function Debug:runCommand(line)
  line = util.trim(line or "")
  if line == "" then return end

  self:echo("> " .. line, "cmd")

  local args = util.splitArgs(line)
  local name = args[1]
  table.remove(args, 1)

  local cmd = self.commands[name]
  if not cmd then
    self:echo("Unknown command '" .. tostring(name) .. "'. Type 'help'.", "error")
    return
  end

  local ok, err = xpcall(function()
    cmd.fn(args, line)
  end, debug.traceback)

  if not ok then
    self:echo("command failed: " .. tostring(err), "error")
    log.error("Console command '%s' failed: %s", line, tostring(err))
  end
end

function Debug:submit()
  local line = util.trim(self.input)
  self.input = ""
  self.caret = 1

  if line == "" then return end
  if self.history[#self.history] ~= line then
    self.history[#self.history + 1] = line
    if #self.history > 200 then table.remove(self.history, 1) end
  end
  self.historyIndex = #self.history + 1
  self:runCommand(line)
end

function Debug:complete()
  local input = self.input
  if input == "" or input:find("%s") then return end

  local matches = {}
  for _, name in ipairs(self.commandOrder) do
    if name:sub(1, #input) == input then
      matches[#matches + 1] = name
    end
  end

  if #matches == 1 then
    self.input = matches[1] .. " "
    self.caret = #self.input + 1
  elseif #matches > 1 then
    local prefix = matches[1]
    for i = 2, #matches do
      while prefix ~= "" and matches[i]:sub(1, #prefix) ~= prefix do
        prefix = prefix:sub(1, #prefix - 1)
      end
    end
    if prefix ~= "" and prefix ~= input then
      self.input = prefix
      self.caret = #self.input + 1
    end
    self:echo(table.concat(matches, "   "), "dim")
  end
end

function Debug:consoleKeypressed(key, isrepeat)
  local ctrl = love.keyboard.isDown("lctrl", "rctrl")

  if key == "escape" then
    self:setConsole(false)
  elseif key == "return" or key == "kpenter" then
    if not isrepeat then self:submit() end
  elseif key == "tab" then
    if not isrepeat then self:complete() end
  elseif key == "backspace" then
    if ctrl then
      local i = self.caret - 1
      while i > 0 and self.input:sub(i, i):match("%s") do i = i - 1 end
      while i > 0 and not self.input:sub(i, i):match("%s") do i = i - 1 end
      self.input = self.input:sub(1, i) .. self.input:sub(self.caret)
      self.caret = i + 1
    elseif self.caret > 1 then
      self.input = self.input:sub(1, self.caret - 2) .. self.input:sub(self.caret)
      self.caret = self.caret - 1
    end
  elseif key == "delete" then
    if self.caret <= #self.input then
      self.input = self.input:sub(1, self.caret - 1) .. self.input:sub(self.caret + 1)
    end
  elseif key == "left" then
    if ctrl then
      local i = self.caret - 1
      while i > 1 and self.input:sub(i, i):match("%s") do i = i - 1 end
      while i > 1 and not self.input:sub(i - 1, i - 1):match("%s") do i = i - 1 end
      self.caret = i
    else
      self.caret = math.max(1, self.caret - 1)
    end
  elseif key == "right" then
    if ctrl then
      local n = #self.input
      local i = self.caret
      while i <= n and self.input:sub(i, i):match("%s") do i = i + 1 end
      while i <= n and not self.input:sub(i, i):match("%s") do i = i + 1 end
      self.caret = i
    else
      self.caret = math.min(#self.input + 1, self.caret + 1)
    end
  elseif key == "home" then
    self.caret = 1
  elseif key == "end" then
    self.caret = #self.input + 1
  elseif key == "up" then
    if #self.history > 0 then
      self.historyIndex = math.max(1, self.historyIndex - 1)
      self.input = self.history[self.historyIndex] or ""
      self.caret = #self.input + 1
    end
  elseif key == "down" then
    if #self.history > 0 then
      self.historyIndex = math.min(#self.history + 1, self.historyIndex + 1)
      if self.historyIndex > #self.history then
        self.input = ""
      else
        self.input = self.history[self.historyIndex] or ""
      end
      self.caret = #self.input + 1
    end
  elseif key == "pageup" then
    self.scroll = self.scroll + 10
  elseif key == "pagedown" then
    self.scroll = math.max(0, self.scroll - 10)
  elseif key == "l" and ctrl then
    self:clearConsole()
  elseif key == "u" and ctrl then
    self.input = ""
    self.caret = 1
  end
end

function Debug:textinput(text)
  if not self.consoleOpen then return end
  self.input = self.input:sub(1, self.caret - 1) .. text .. self.input:sub(self.caret)
  self.caret = self.caret + #text
end

function Debug:setConsole(open)
  if open == nil then open = not self.consoleOpen end
  if self.consoleOpen == open then return end
  self.consoleOpen = open
  if open then
    self.scroll = 0
    self.historyIndex = #self.history + 1
    self:echo("console opened (game paused while typing)", "dim")
  else
    self.scroll = 0
  end
  log.info("console %s", open and "opened" or "closed")
end

function Debug:toggleConsole()
  self:setConsole(not self.consoleOpen)
end

function Debug:setDrawEnabled(enabled)
  self.drawEnabled = enabled
  dd.enabled = enabled
end

function Debug:toast(text, kind, duration)
  duration = duration or 3.5
  self.toasts[#self.toasts + 1] = {
    text = tostring(text),
    kind = kind or "info",
    remaining = duration,
    duration = duration,
  }
  while #self.toasts > 5 do
    table.remove(self.toasts, 1)
  end
end

function Debug:status()
  if self.consoleOpen then return "CONSOLE" end
  if self.paused then return "PAUSED" end
  if self.timeScale ~= 1 then return string.format("TIME x%.2f", self.timeScale) end
  return "RUNNING"
end

function Debug:statusColor()
  if self.consoleOpen then return C.accent end
  if self.paused then return C.yellow end
  if self.timeScale ~= 1 then return C.orange end
  return C.green
end

function Debug:timeStep(dt)
  if self.consoleOpen or self.paused then
    if self.stepFrames > 0 then
      self.stepFrames = self.stepFrames - 1
      return 1 / 60
    end
    return 0
  end
  return dt * self.timeScale
end

function Debug:togglePause()
  self.paused = not self.paused
  self:toast(self.paused and "Paused" or "Resumed", self.paused and "warn" or "ok", 1.2)
  log.info("game %s", self.paused and "paused" or "resumed")
end

function Debug:screenshot(name)
  name = name or ("screenshot-" .. os.date("%Y%m%d-%H%M%S") .. ".png")
  if not name:match("%.png$") then name = name .. ".png" end
  love.graphics.captureScreenshot(function(imageData)
    local ok, err = pcall(function()
      imageData:encode("png", name)
    end)
    if ok then
      Debug:echo("screenshot saved: " .. name, "ok")
      log.info("screenshot saved: %s", name)
    else
      Debug:echo("screenshot failed: " .. tostring(err), "error")
      log.error("screenshot failed: %s", tostring(err))
    end
  end)
  return name
end

-------------------------------------------------------------------------------
-- input
-------------------------------------------------------------------------------

function Debug:keypressed(key, scancode, isrepeat)
  if not isrepeat then
    if key == "f1" then
      self.hudVisible = not self.hudVisible
      return true
    elseif key == "f2" or key == "`" then
      self:setConsole(not self.consoleOpen)
      return true
    elseif key == "f3" then
      self:setDrawEnabled(not self.drawEnabled)
      self:toast("debug draw " .. (self.drawEnabled and "on" or "off"), "info", 1.2)
      return true
    elseif key == "f4" then
      self.showProfiler = not self.showProfiler
      return true
    elseif key == "f5" then
      local App = self:getApp()
      if App then
        local ok = App:restart()
        if ok == false then
          self:toast("scene restart blocked in multiplayer", "warn", 2)
        else
          self:toast("scene restarted", "ok", 1.5)
        end
      end
      return true
    elseif key == "f6" then
      self:togglePause()
      return true
    elseif key == "f7" then
      self.paused = true
      self.stepFrames = self.stepFrames + 1
      return true
    elseif key == "f8" then
      self.timeScale = self.timeScale == 0.25 and 1 or 0.25
      self:toast(string.format("time x%.2f", self.timeScale), "info", 1.2)
      return true
    elseif key == "f9" then
      self:screenshot()
      return true
    elseif key == "f11" then
      local ok, err = pcall(function()
        love.window.setFullscreen(not love.window.getFullscreen(), "desktop")
      end)
      if not ok then self:toast("fullscreen failed: " .. tostring(err), "error") end
      return true
    end
  end

  if self.consoleOpen then
    self:consoleKeypressed(key, isrepeat)
    return true
  end

  return false
end

function Debug:wheelmoved(x, y)
  if not self.consoleOpen then return false end
  self.scroll = math.max(0, self.scroll + y * 3)
  return true
end

-------------------------------------------------------------------------------
-- update
-------------------------------------------------------------------------------

function Debug:update(dt)
  self.frameMs = dt * 1000
  self.frameMsAvg = util.damp(self.frameMsAvg, self.frameMs, 4, dt)
  self.frameMsPeak = 0

  local graph = self.graph
  graph[#graph + 1] = self.frameMs
  if #graph > self.maxGraph then table.remove(graph, 1) end

  for _, ms in ipairs(graph) do
    if ms > self.frameMsPeak then self.frameMsPeak = ms end
  end

  if dt >= 0.004 then
    self.frameMsAvg = util.damp(self.frameMsAvg, self.frameMs, 4, dt)
  end
  self.fpsAvg = 1000 / math.max(0.001, self.frameMsAvg)

  -- LÖVE's counter is refreshed once a second; fall back to the smoothed
  -- average during the first second so the HUD never reads "0 FPS".
  local timerFps = love.timer.getFPS()
  self.fps = timerFps > 0 and timerFps or math.floor(self.fpsAvg + 0.5)

  self.memMB = collectgarbage("count") / 1024
  self.uptime = love.timer.getTime() - self.bootTime

  for i = #self.toasts, 1, -1 do
    local toast = self.toasts[i]
    toast.remaining = toast.remaining - dt
    if toast.remaining <= 0 then
      table.remove(self.toasts, i)
    end
  end
end

-------------------------------------------------------------------------------
-- drawing
-------------------------------------------------------------------------------

local function stateColor(fps)
  if fps >= 55 then return C.green end
  if fps >= 30 then return C.yellow end
  return C.red
end

function Debug:drawGraph(x, y, w, h)
  draw.rect("fill", x, y, w, h, C.bgTop, 3, 0.92)
  draw.rect("line", x, y, w, h, C.borderSoft, 3)

  local maxMs = 50
  local function lineAt(ms, color)
    local ly = y + h - util.clamp(ms / maxMs, 0, 1) * h
    draw.set(color, 0.5)
    love.graphics.setLineWidth(1)
    love.graphics.line(x, ly, x + w, ly)
  end

  lineAt(16.7, C.green)
  lineAt(33.3, C.orange)

  local graph = self.graph
  if #graph >= 2 then
    local points = {}
    local step = w / math.max(1, self.maxGraph - 1)
    local offset = w - (#graph - 1) * step
    for i = 1, #graph do
      local px = x + offset + (i - 1) * step
      local py = y + h - util.clamp(graph[i] / maxMs, 0, 1) * h
      points[#points + 1] = px
      points[#points + 1] = py
    end
    if #points >= 4 then
      draw.set(stateColor(self.fpsAvg), 0.95)
      love.graphics.setLineWidth(1.5)
      love.graphics.line(points)
    end
  end

  draw.text("16.7", x + 3, y + 1, { font = fonts.mono(9), color = C.faint })
end

function Debug:drawHud()
  local fontMono = fonts.mono(12)
  local fontSmall = fonts.mono(10)
  local fontTitle = fonts.ui(18)
  local fontBig = fonts.ui(30)

  local watches = self:watchList()
  local shownWatches = math.min(#watches, 12)
  local x, y, w = 14, 14, 286
  local rowCount = 7
  local h = 100 + rowCount * 15 + 58 + (10 + 14 + shownWatches * 16) + 22

  draw.panel(x, y, w, h, { radius = 6 })

  draw.text("DOGFIGHT", x + 12, y + 9, { font = fontTitle, color = C.accent })
  draw.text("DEV", x + w - 42, y + 12, { font = fontMono, color = C.orange })
  draw.text("debug overlay", x + w - 100, y + 32, { font = fontSmall, color = C.dim, width = 88, align = "right" })
  draw.set(C.borderSoft)
  love.graphics.setLineWidth(1)
  love.graphics.line(x + 12, y + 48, x + w - 12, y + 48)

  local fpsColor = stateColor(self.fpsAvg)
  draw.text(tostring(self.fps), x + 12, y + 52, { font = fontBig, color = fpsColor })
  draw.text("FPS", x + 12 + fontBig:getWidth(tostring(self.fps)) + 6, y + 64, { font = fontMono, color = C.dim })
  draw.text(string.format("%.1f ms avg", self.frameMsAvg), x + 12, y + 64,
    { font = fontMono, color = C.dim, width = w - 24, align = "right" })

  local ry = y + 96
  local function row(label, value, color)
    draw.text(label, x + 12, ry, { font = fontMono, color = C.dim })
    draw.text(value, x + 12, ry, { font = fontMono, color = color or C.text, width = w - 24, align = "right" })
    ry = ry + 15
  end

  row("frame", string.format("%.2f / %.1f ms", self.frameMs, self.frameMsPeak), C.text)
  row("draw", string.format("%d calls", self.drawCalls), C.text)
  row("memory", string.format("%.1f MB", self.memMB), C.text)
  row("state", self:status(), self:statusColor())
  row("timescale", string.format("%.2f x", self.timeScale), self.timeScale == 1 and C.dim or C.orange)
  row("seed", tostring(self.seed or "?"), C.dim)
  row("uptime", string.format("%02d:%02d", math.floor(self.uptime / 60), math.floor(self.uptime % 60)), C.dim)

  local gy = ry + 4
  self:drawGraph(x + 12, gy, w - 24, 44)

  local wy = gy + 54
  if #watches > 0 then
    draw.text("WATCH", x + 12, wy, { font = fontSmall, color = C.accentDim })
    wy = wy + 14
    for i = 1, shownWatches do
      local item = watches[i]
      draw.text(item.name, x + 12, wy, { font = fontMono, color = C.dim })
      draw.text(item.value, x + 12, wy, { font = fontMono, color = item.color, width = w - 24, align = "right" })
      wy = wy + 16
    end
  end

  draw.text("F1 hide   F2 console   F3 draw", x + 12, y + h - 18,
    { font = fontSmall, color = C.faint })
end

function Debug:drawProfiler()
  if not self.showProfiler then return end
  local stats = profiler.stats()
  if #stats == 0 then return end

  local font = fonts.mono(11)
  local sw = love.graphics.getWidth()
  local w = 244
  local rows = math.min(#stats, 9)
  local h = 30 + rows * 16 + 8
  local x = sw - w - 14
  local y = 14

  draw.panel(x, y, w, h, { radius = 6 })
  draw.text("PROFILER  ms/frame", x + 10, y + 8, { font = fonts.ui(12), color = C.accent })
  draw.set(C.borderSoft)
  love.graphics.line(x + 10, y + 27, x + w - 10, y + 27)

  local ry = y + 32
  for i = 1, rows do
    local s = stats[i]
    local frac = util.clamp(s.avg / 16.7, 0, 1)
    draw.rect("fill", x + 10, ry + 11, w - 20, 2, C.faint, 1, 0.5)
    draw.rect("fill", x + 10, ry + 11, (w - 20) * frac, 2, C.accentDim, 1)
    draw.text(util.truncate(font, s.name, w - 92), x + 10, ry, { font = font, color = C.text })
    draw.text(string.format("%.2f", s.avg), x + 10, ry, { font = font, color = C.accent, width = w - 20, align = "right" })
    ry = ry + 16
  end
end

function Debug:drawToasts()
  local font = fonts.ui(14)
  local sw = love.graphics.getWidth()
  local y = 14
  for _, toast in ipairs(self.toasts) do
    local alpha = util.clamp(toast.remaining / 0.35, 0, 1)
    local w = math.min(440, math.max(240, font:getWidth(toast.text) + 46))
    local x = (sw - w) * 0.5
    local color = kindColors[toast.kind] or C.text

    draw.rect("fill", x, y, w, 30, { 0.045, 0.055, 0.075, 0.94 * alpha }, 5)
    draw.rect("fill", x, y, 4, 30, color, 2, alpha)
    draw.text(toast.text, x + 14, y + 7, { font = font, color = C.text, alpha = alpha, width = w - 24,
      align = "left" })
    y = y + 36
  end
end

function Debug:rebuildWrap(innerWidth, font)
  local wrapped = {}
  local first = math.max(1, #self.lines - 200)
  for i = first, #self.lines do
    local entry = self.lines[i]
    local parts = util.wrapText(font, entry.text, innerWidth)
    for _, part in ipairs(parts) do
      wrapped[#wrapped + 1] = { text = part, kind = entry.kind }
    end
  end
  self._wrapped = wrapped
  self._wrapWidth = innerWidth
  self._wrapDirty = false
end

function Debug:drawConsole()
  local sw, sh = love.graphics.getDimensions()
  local font = fonts.mono(15)
  local small = fonts.mono(10)

  local x = 16
  local w = sw - 32
  local h = math.min(430, math.floor(sh * 0.46))
  local y = sh - h - 16

  draw.panel(x, y, w, h, {
    color = { 0.028, 0.037, 0.050, 1 },
    borderColor = C.accentDim,
    shadow = true,
  })

  draw.text("CONSOLE", x + 12, y + 9, { font = fonts.ui(15), color = C.accent })
  draw.text("help  /  Tab complete  /  PgUp/PgDn scroll  /  Esc close", x + 12, y + 13,
    { font = small, color = C.dim, width = w - 24, align = "right" })
  draw.set(C.borderSoft)
  love.graphics.setLineWidth(1)
  love.graphics.line(x + 10, y + 32, x + w - 10, y + 32)

  local innerWidth = w - 28
  if self._wrapDirty or self._wrapWidth ~= innerWidth then
    self:rebuildWrap(innerWidth, font)
  end

  local top = y + 40
  local inputY = y + h - 36
  local bottom = inputY - 8
  local lineH = 18
  local visible = math.max(1, math.floor((bottom - top) / lineH))
  local total = #self._wrapped
  local maxScroll = math.max(0, total - visible)
  self.scroll = util.clamp(self.scroll, 0, maxScroll)

  local first = math.max(1, total - visible - math.floor(self.scroll) + 1)
  love.graphics.setScissor(x + 8, top, w - 16, bottom - top)
  for i = first, math.min(total, first + visible - 1) do
    local item = self._wrapped[i]
    local color = kindColors[item.kind] or C.text
    draw.text(item.text, x + 14, top + (i - first) * lineH, { font = font, color = color })
  end
  love.graphics.setScissor()

  if self.scroll > 0 then
    draw.text(string.format("UP %d", math.floor(self.scroll)), x + 12, inputY - 18,
      { font = small, color = C.orange, width = w - 24, align = "right" })
  end

  draw.rect("fill", x + 2, inputY - 4, w - 4, 28, C.panelRaised, 3, 0.75)
  draw.set(C.accent)
  love.graphics.setFont(font)
  love.graphics.print(">", x + 12, inputY)

  local textX = x + 12 + font:getWidth("> ")
  local avail = x + w - 24 - textX
  local before = self.input:sub(1, self.caret - 1)
  local caretOffset = font:getWidth(before)
  local offset = math.max(0, caretOffset - avail + 12)

  love.graphics.setScissor(textX, inputY - 2, avail, 24)
  if self.input == "" then
    draw.text("type a command...", textX, inputY, { font = font, color = C.faint })
  end
  draw.text(self.input, textX - offset, inputY, { font = font, color = C.text })
  if love.timer.getTime() % 1 < 0.55 then
    local cx = textX + caretOffset - offset
    if cx >= textX - 1 and cx <= textX + avail then
      draw.rect("fill", cx, inputY + 1, 2, 17, C.accent, 1)
    end
  end
  love.graphics.setScissor()
end

function Debug:draw()
  if not self.initialized then return end
  love.graphics.push("all")
  love.graphics.origin()
  love.graphics.setScissor()

  if self.hudVisible then
    self:drawHud()
    self:drawProfiler()
  end
  self:drawToasts()
  if self.consoleOpen then
    self:drawConsole()
  end

  -- Read after drawing so the HUD reports the current frame's calls next frame.
  self.drawCalls = love.graphics.getStats().drawcalls or 0

  love.graphics.pop()
end

return Debug
