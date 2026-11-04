-- Gameplay key bindings backed by settings.json.

local Settings = require("src.game.settings")

local Controls = {}

local LABELS = {
  up = "UP", down = "DOWN", left = "LEFT", right = "RIGHT",
  space = "SPACE", lshift = "L-SHIFT", rshift = "R-SHIFT",
  lctrl = "L-CTRL", rctrl = "R-CTRL", lalt = "L-ALT", ralt = "R-ALT",
}

function Controls.keys(action)
  return Settings.data.bindings[action] or {}
end

function Controls.isDown(action)
  local key = Controls.keys(action)
  return key ~= nil and love.keyboard.isDown(key)
end

function Controls.label(action)
  local key = Controls.keys(action)
  return LABELS[key] or key:upper()
end

function Controls.bind(action, key)
  key = tostring(key or ""):lower()
  if key == "" or key == "escape" then return false end
  Settings.data.bindings[action] = key
  Settings.save()
  return true
end

function Controls.reset()
  Settings.data.bindings = {
    throttleUp = "w",
    throttleDown = "s",
    pitchLeft = "a",
    pitchRight = "d",
    fire = "space",
  }
  Settings.save()
end

return Controls
