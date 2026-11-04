-- errors.lua
-- Custom crash handler: logs a crash report, freezes the game on a readable
-- screen with the full traceback, and offers restart / copy / quit.

local draw = require("src.core.draw")
local fonts = require("src.core.fonts")
local log = require("src.core.log")
local util = require("src.core.util")

local errors = {}

local C = draw.C

local function writeCrash(msg)
  love.filesystem.createDirectory("logs")
  local stamp = os.date("%Y%m%d-%H%M%S")
  local path = "logs/crash-" .. stamp .. ".log"
  local body = table.concat({
    "======================================================================",
    " YUGOSLAVIAN WAR crash report",
    " time : " .. os.date("%Y-%m-%d %H:%M:%S"),
    " love : " .. table.concat({ love.getVersion() }, "."),
    " os   : " .. tostring(love.system.getOS()),
    " jit  : " .. tostring(jit and jit.version or "?"),
    " save : " .. tostring(love.filesystem.getSaveDirectory()),
    "======================================================================",
    "",
    tostring(msg),
    "",
    "Last log lines:",
    "----------------------------------------------------------------------",
  }, "\n")

  for _, entry in ipairs(log.tail(40)) do
    body = body .. string.format("[%s] %s %s\n", entry.time, entry.level:upper(), entry.message)
  end

  love.filesystem.write(path, body)
  return path
end

local function safeDraw(fn)
  local ok, err = pcall(fn)
  if not ok then
    love.graphics.setColor(1, 0.4, 0.4, 1)
    love.graphics.print("Error screen failed: " .. tostring(err), 20, 20)
  end
end

local function runErrorLoop(state)
  local mono = fonts.mono(14)
  local ui = fonts.ui(13)
  local titleFont = fonts.ui(22)

  return function()
    for name, a, b, c in love.event.poll() do
      if name == "quit" then
        return a or 0
      elseif name == "keypressed" then
        if a == "escape" then
          return 1
        elseif a == "r" then
          return "restart"
        elseif a == "c" then
          local ok = pcall(love.system.setClipboardText, state.text)
          state.copied = ok
        elseif a == "up" then
          state.scroll = math.max(0, state.scroll - 3)
        elseif a == "down" then
          state.scroll = state.scroll + 3
        elseif a == "pageup" then
          state.scroll = math.max(0, state.scroll - 20)
        elseif a == "pagedown" then
          state.scroll = state.scroll + 20
        elseif a == "home" then
          state.scroll = 0
        elseif a == "end" then
          state.scroll = 999999
        end
      elseif name == "wheelmoved" then
        state.scroll = math.max(0, state.scroll - b * 3)
      end
    end

    local sw, sh = love.graphics.getDimensions()
    pcall(love.graphics.setCanvas)
    love.graphics.origin()
    love.graphics.setScissor()
    love.graphics.clear(C.bgTop[1] * 1.4, C.bgTop[2] * 1.4, C.bgTop[3] * 1.5, 1)

    safeDraw(function()
      -- header
      draw.rect("fill", 0, 0, sw, 74, { 0.18, 0.035, 0.045, 1 })
      draw.rect("fill", 0, 74, sw, 2, C.red)
      draw.text("UNHANDLED ERROR", 32, 18, { font = titleFont, color = C.red })
      draw.text("YUGOSLAVIAN WAR // crash screen", 32, 48, { font = ui, color = C.dim })

      local lines = util.wrapText(mono, state.text, sw - 96)
      local top = 100
      local bottom = sh - 92
      local lineH = 18
      local visible = math.max(1, math.floor((bottom - top) / lineH))
      local maxScroll = math.max(0, #lines - visible)
      state.scroll = util.clamp(state.scroll, 0, maxScroll)

      love.graphics.setScissor(32, top, sw - 64, bottom - top)
      for i = 1, visible do
        local line = lines[state.scroll + i]
        if not line then break end
        local color = C.text
        if line:match("^stack traceback") then color = C.orange end
        if line:match("^%[C%]") then color = C.dim end
        draw.text(line, 36, top + (i - 1) * lineH, { font = mono, color = color })
      end
      love.graphics.setScissor()

      local y = sh - 76
      draw.rect("fill", 0, y - 10, sw, 86, { 0.03, 0.04, 0.055, 1 })
      draw.rect("fill", 0, y - 10, sw, 1, C.borderSoft)

      if state.copied then
        draw.text("Traceback copied to clipboard.", 34, y, { font = ui, color = C.green })
      elseif state.crashPath then
        draw.text("Crash report: " .. tostring(state.crashPath) .. "  (in the LÖVE save directory)", 34, y,
          { font = ui, color = C.dim })
      else
        draw.text("Crash report could not be written.", 34, y, { font = ui, color = C.orange })
      end

      local hint = "R  restart      C  copy traceback      PgUp/PgDn  scroll      Esc  quit"
      draw.text(hint, 34, y + 26, { font = ui, color = C.text })

      local scrollInfo = string.format("%d/%d", state.scroll + 1, math.max(1, #lines))
      draw.text(scrollInfo, sw - 120, y + 26, { font = ui, color = C.faint, width = 86, align = "right" })
      draw.text("Full console output is in the log file / terminal window.", 34, y + 48,
        { font = fonts.ui(11), color = C.faint })
    end)

    love.graphics.present()
    love.timer.sleep(0.001)

    if errors.autoExit then
      if not state.captured then
        state.captured = true
        pcall(love.graphics.captureScreenshot, function(imageData)
          pcall(function() imageData:encode("png", "preview-crash.png") end)
        end)
      end
      state.frames = state.frames + 1
      if state.frames >= 4 then
        return 1
      end
    end

    return nil
  end
end

function errors.handle(msg)
  local text = tostring(msg)
  if not text:find("stack traceback", 1, true) then
    text = text .. "\n\n" .. debug.traceback("", 2)
  end

  local crashPath
  local ok, result = pcall(writeCrash, text)
  if ok then crashPath = result end

  pcall(log.fatal, "Unhandled error:\n%s", text)

  local state = {
    text = text,
    scroll = 0,
    copied = false,
    crashPath = crashPath,
    frames = 0,
  }

  return runErrorLoop(state)
end

function errors.install(opts)
  errors.autoExit = opts and (opts.smoke or opts.test or opts.shot) or false
  love.errorhandler = errors.handle
  love.threaderror = function(_, err)
    pcall(log.error, "Thread error: %s", tostring(err))
  end
end

return errors
