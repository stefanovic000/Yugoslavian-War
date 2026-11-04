-- Persistent player settings. Stored as JSON in the LÖVE save directory.

local json = require("lib.json")

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
}

local function sanitize(data)
  if type(data) ~= "table" then data = {} end
  local out = {}
  for k, v in pairs(DEFAULTS) do out[k] = v end

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
  local current = love.window.getFullscreen()
  if current ~= full then
    pcall(love.window.setFullscreen, full, "desktop")
  end
end

function Settings.reset()
  Settings.data = sanitize(DEFAULTS)
  Settings.save()
end

return Settings
