-- log.lua
-- Structured logging to the console, a session file, and an in-memory ring
-- buffer (used by the in-game console). The console window is the primary
-- debugging surface on Windows; the file is the post-mortem record.

local util = require("src.core.util")

local log = {}
log.levels = { trace = 1, debug = 2, info = 3, warn = 4, error = 5, fatal = 6, off = 99 }
log.level = log.levels.debug
log.levelName = "debug"
log.history = {}
log.maxHistory = 600
log.file = nil
log.saveDir = nil
log.initialized = false
log.startClock = 0
log.onEntry = nil

local shortSource

function shortSource(source)
  source = tostring(source or "?"):gsub("^@", ""):gsub("\\", "/")
  local rel = source:match("(src/[%w%-_/%.]+)$")
    or source:match("(tests/[%w%-_/%.]+)$")
    or source
  if #rel > 48 then
    rel = rel:match("([^/]+)$") or rel
  end
  return rel
end

local function clockString()
  local t = love.timer.getTime()
  local ms = math.floor((t % 1) * 1000)
  return os.date("%H:%M:%S") .. string.format(".%03d", ms)
end

local function pushHistory(entry)
  local h = log.history
  h[#h + 1] = entry
  if #h > log.maxHistory then
    table.remove(h, 1)
  end
end

local function sessionHeader()
  local loveVersion = table.concat({ love.getVersion() }, ".")
  local args = table.concat(arg or {}, " ")
  return table.concat({
    "======================================================================",
    " YUGOSLAVIAN WAR session log",
    " started : " .. os.date("%Y-%m-%d %H:%M:%S"),
    " love    : " .. loveVersion,
    " os      : " .. tostring(love.system.getOS()) .. " / " .. table.concat({ jit and jit.version or "?" }),
    " args    : " .. args,
    " save    : " .. tostring(log.saveDir),
    "======================================================================",
    "",
  }, "\n")
end

local function rotate()
  local ok, items = pcall(love.filesystem.getDirectoryItems, "logs")
  if not ok or not items then return end
  local sessions, crashes = {}, {}
  for _, name in ipairs(items) do
    if name:match("^session%-%d+%-%d+%.log$") then
      sessions[#sessions + 1] = name
    elseif name:match("^crash%-%d+%-%d+%.log$") then
      crashes[#crashes + 1] = name
    end
  end
  table.sort(sessions)
  table.sort(crashes)
  for i = 1, #sessions - 10 do
    pcall(love.filesystem.remove, "logs/" .. sessions[i])
  end
  for i = 1, #crashes - 20 do
    pcall(love.filesystem.remove, "logs/" .. crashes[i])
  end
end

function log.init(opts)
  opts = opts or {}
  log.startClock = love.timer.getTime()

  if opts.logLevel and log.levels[opts.logLevel] then
    log.level = log.levels[opts.logLevel]
    log.levelName = opts.logLevel
  elseif opts.debug then
    log.level = log.levels.trace
    log.levelName = "trace"
  end

  local ok, err = pcall(function()
    log.saveDir = love.filesystem.getSaveDirectory()
    love.filesystem.createDirectory("logs")
    local stamp = os.date("%Y%m%d-%H%M%S")
    log.file = string.format("logs/session-%s.log", stamp)
    love.filesystem.write(log.file, sessionHeader())
    rotate()
  end)
  if not ok then
    log.file = nil
    print("[log] file logging disabled: " .. tostring(err))
  end

  log.initialized = true
  log.info("logger ready (level=%s, file=%s)", log.levelName, tostring(log.file))
end

function log.setLevel(name)
  if not log.levels[name] then
    return false, "unknown level '" .. tostring(name) .. "' (trace/debug/info/warn/error/fatal/off)"
  end
  log.level = log.levels[name]
  log.levelName = name
  return true
end

local function emit(levelName, message, stackLevel)
  local levelNum = log.levels[levelName] or 3
  if levelNum < log.level then return end

  local source = ""
  local startLevel = stackLevel or 4
  for level = startLevel, startLevel + 3 do
    local info = debug.getinfo(level, "Sl")
    if not info then break end
    if info.what ~= "C" then
      source = shortSource(info.source) .. ":" .. tostring(info.currentline)
      break
    end
  end

  local timeStr = clockString()
  local line = string.format("[%s] %-5s %s%s",
    timeStr, levelName:upper(), source ~= "" and ("[" .. source .. "] ") or "", message)

  print(line)

  if log.file then
    pcall(love.filesystem.append, log.file, line .. "\n")
  end

  local entry = { level = levelName, message = message, source = source, time = timeStr }
  pushHistory(entry)

  if log.onEntry then
    pcall(log.onEntry, entry)
  end
end

local function formatMessage(fmt, ...)
  if select("#", ...) == 0 then return tostring(fmt) end
  local ok, msg = pcall(string.format, fmt, ...)
  if ok then return msg end
  local parts = { tostring(fmt) }
  for i = 1, select("#", ...) do
    parts[#parts + 1] = tostring((select(i, ...)))
  end
  return table.concat(parts, " ")
end

local function write(levelName, fmt, ...)
  local levelNum = log.levels[levelName] or 3
  if levelNum < log.level then return end
  emit(levelName, formatMessage(fmt, ...), 4)
end

function log.trace(fmt, ...) write("trace", fmt, ...) end
function log.debug(fmt, ...) write("debug", fmt, ...) end
function log.info(fmt, ...) write("info", fmt, ...) end
function log.warn(fmt, ...) write("warn", fmt, ...) end
function log.error(fmt, ...) write("error", fmt, ...) end
function log.fatal(fmt, ...) write("fatal", fmt, ...) end

function log.tail(count)
  local out = {}
  local h = log.history
  local first = math.max(1, #h - (count or 20) + 1)
  for i = first, #h do out[#out + 1] = h[i] end
  return out
end

function log.path()
  if not log.file then return "(no file)" end
  return tostring(log.saveDir) .. "/" .. log.file
end

function log.clearHistory()
  log.history = {}
end

return log
