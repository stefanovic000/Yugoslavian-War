-- Persistent player settings. Stored as JSON in the LÖVE save directory.

local json = require("lib.json")
local Aircraft = require("shared.aircraft")

local Settings = {
  path = "settings.json",
  data = nil,
}

local DEFAULTS = {
  callsign = "Pilot",
  serverHost = "132.226.207.140",
  serverPort = 7777,
  hostCustom = false,
  fullscreen = false,
  showFps = false,
  screenShake = true,
  masterVolume = 1.0,
  effectsVolume = 1.0,
  engineVolume = 1.0,
  resolution = "1280x720",
  aircraft = "ik3",
  bindings = {
    throttleUp = "w",
    throttleDown = "s",
    pitchLeft = "a",
    pitchRight = "d",
    fire = "space",
  },
}

local BIND_ACTIONS = {
  "throttleUp", "throttleDown", "pitchLeft", "pitchRight", "fire",
}

local RESOLUTIONS = {
  { w = 960, h = 540 },
  { w = 1280, h = 720 },
  { w = 1600, h = 900 },
  { w = 1920, h = 1080 },
  { w = 2560, h = 1440 },
}
Settings.RESOLUTIONS = RESOLUTIONS

local function resolutionLabel(r)
  return tostring(r.w) .. "x" .. tostring(r.h)
end

local function resolutionIndex(value)
  for i, r in ipairs(RESOLUTIONS) do
    if resolutionLabel(r) == value then return i end
  end
  return 2
end
Settings.resolutionIndex = resolutionIndex

local function sanitizeKey(key)
  if type(key) ~= "string" then return nil end
  key = key:lower():gsub("%s", "")
  if key == "" or #key > 24 then return nil end
  return key
end

local function sanitizeBindings(data)
  local out = {}
  for _, action in ipairs(BIND_ACTIONS) do
    local value = type(data) == "table" and data[action] or nil
    out[action] = sanitizeKey(value) or DEFAULTS.bindings[action]
  end
  return out
end

local function sanitize(data)
  if type(data) ~= "table" then data = {} end
  local out = {}
  for k, v in pairs(DEFAULTS) do out[k] = v end
  out.bindings = sanitizeBindings(data.bindings)

  if type(data.callsign) == "string" then
    out.callsign = data.callsign:gsub("[%c]", ""):sub(1, 14)
    if out.callsign == "" then out.callsign = DEFAULTS.callsign end
  end
  if type(data.serverHost) == "string" then
    out.serverHost = data.serverHost:gsub("[%c%s]", ""):sub(1, 64)
    if out.serverHost == "" then out.serverHost = DEFAULTS.serverHost end
  end
  if type(data.serverPort) == "number" then
    out.serverPort = math.max(1, math.min(65535, math.floor(data.serverPort)))
  end
  out.fullscreen = data.fullscreen == true
  out.showFps = data.showFps == true
  out.screenShake = data.screenShake ~= false
  out.hostCustom = data.hostCustom == true
  out.masterVolume = math.max(0, math.min(1, tonumber(data.masterVolume) or DEFAULTS.masterVolume))
  out.effectsVolume = math.max(0, math.min(1, tonumber(data.effectsVolume) or DEFAULTS.effectsVolume))
  out.engineVolume = math.max(0, math.min(2, tonumber(data.engineVolume) or DEFAULTS.engineVolume))
  out.resolution = resolutionLabel(RESOLUTIONS[resolutionIndex(data.resolution)])
  out.aircraft = Aircraft.normalize(data.aircraft)
  return out
end

function Settings.load()
  Settings.data = sanitize(DEFAULTS)
  local raw = love.filesystem.read(Settings.path)
  if raw then
    local ok, decoded = pcall(json.decode, raw)
    if ok and type(decoded) == "table" then
      Settings.data = sanitize(decoded)
      -- Migrate the old localhost default. A host explicitly chosen and saved
      -- by the player is marked with hostCustom and is left alone.
      if not Settings.data.hostCustom
        and (Settings.data.serverHost == "127.0.0.1" or Settings.data.serverHost == "localhost") then
        Settings.data.serverHost = DEFAULTS.serverHost
      end
    end
  end
  return Settings.data
end

function Settings.save()
  local ok, encoded = pcall(json.encode, Settings.data)
  if not ok then return false, encoded end
  local wok, err = love.filesystem.write(Settings.path, encoded)
  return wok, err
end

function Settings.apply()
  local full = Settings.data.fullscreen == true
  if full then
    pcall(love.window.setFullscreen, true, "desktop")
  else
    pcall(love.window.setFullscreen, false)
    local r = RESOLUTIONS[resolutionIndex(Settings.data.resolution)]
    pcall(love.window.setMode, r.w, r.h, {
      resizable = true, vsync = 1, minwidth = 960, minheight = 540,
      highdpi = false,
    })
  end
end

function Settings.reset()
  Settings.data = sanitize(DEFAULTS)
  Settings.save()
end

return Settings
