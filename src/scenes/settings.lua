-- settings.lua
-- Callsign, network, display, controls and audio.

local App = require("src.app")
local Settings = require("src.game.settings")
local Controls = require("src.game.controls")
local Sky = require("src.game.sky")
local View = require("src.game.view")
local UI = require("src.ui.ui")
local log = require("src.core.log")

local SettingsScene = { name = "settings", module = "src.scenes.settings" }

local TABS = { "GAME", "CONTROLS", "AUDIO" }

local FIELDS = {
  { key = "callsign", label = "CALLSIGN", x = 86, y = 112, w = 220, max = 14 },
  { key = "serverHost", label = "SERVER ADDRESS", x = 86, y = 166, w = 220, max = 64 },
  { key = "serverPort", label = "SERVER PORT", x = 86, y = 220, w = 100, max = 5 },
}

local ACTIONS = {
  { key = "throttleUp", label = "THROTTLE UP" },
  { key = "throttleDown", label = "THROTTLE DOWN" },
  { key = "pitchLeft", label = "PITCH LEFT" },
  { key = "pitchRight", label = "PITCH RIGHT" },
  { key = "fire", label = "FIRE" },
}

function SettingsScene:enter()
  local data = Settings.data
  self.values = {
    callsign = data.callsign,
    serverHost = data.serverHost,
    serverPort = tostring(data.serverPort),
  }
  self.focusIndex = 1
  self.caret = #self.values.callsign + 1
  self.hover = nil
  self.status = nil
  self.tab = 1
  self.awaitBind = nil
  self.dragSlider = nil
end

function SettingsScene:save()
  local port = tonumber(self.values.serverPort) or 7777
  port = math.max(1, math.min(65535, math.floor(port)))

  Settings.data.callsign = (self.values.callsign:gsub("%s+$", ""))
  if Settings.data.callsign == "" then Settings.data.callsign = "Pilot" end
  Settings.data.serverHost = self.values.serverHost ~= "" and self.values.serverHost or "132.226.207.140"
  Settings.data.hostCustom = true
  Settings.data.serverPort = port
  local ok, err = Settings.save()
  Settings.apply()

  self.values.callsign = Settings.data.callsign
  self.values.serverHost = Settings.data.serverHost
  self.values.serverPort = tostring(port)
  if ok then
    self.status = "SAVED."
    log.info("settings saved (host=%s port=%d)", Settings.data.serverHost, port)
  else
    self.status = "SAVE FAILED."
    log.error("settings save failed: %s", tostring(err))
  end
end

function SettingsScene:setFullscreen(v)
  Settings.data.fullscreen = v
  Settings.apply()
  Settings.save()
  View.resize(love.graphics.getDimensions())
end

function SettingsScene:focusField(index)
  self.focusIndex = ((index - 1) % #FIELDS) + 1
  local f = FIELDS[self.focusIndex]
  self.caret = #self.values[f.key] + 1
end

function SettingsScene:setSlider(name, mx)
  local v = math.max(0, math.min(1, (mx - 86) / 360))
  Settings.data[name] = v
end

function SettingsScene:keypressed(key)
  if self.awaitBind then
    if key == "escape" then
      self.awaitBind = nil
    else
      Controls.bind(self.awaitBind, key)
      self.awaitBind = nil
      self.status = "CONTROL REBOUND."
    end
    return
  end

  if key == "escape" then
    self:save()
    App:pop()
    return
  end

  if self.tab == 1 then
    if key == "tab" then
      self:focusField(self.focusIndex + 1)
      return
    elseif key == "up" then
      self:focusField(self.focusIndex - 1)
      return
    elseif key == "down" then
      self:focusField(self.focusIndex + 1)
      return
    elseif key == "return" or key == "kpenter" then
      self:save()
      return
    end

    local f = FIELDS[self.focusIndex]
    local value = self.values[f.key]

    if key == "backspace" then
      if self.caret > 1 then
        value = value:sub(1, self.caret - 2) .. value:sub(self.caret)
        self.caret = self.caret - 1
      end
    elseif key == "delete" then
      if self.caret <= #value then
        value = value:sub(1, self.caret - 1) .. value:sub(self.caret + 1)
      end
    elseif key == "left" then
      self.caret = math.max(1, self.caret - 1)
    elseif key == "right" then
      self.caret = math.min(#value + 1, self.caret + 1)
    elseif key == "home" then
      self.caret = 1
    elseif key == "end" then
      self.caret = #value + 1
    end

    self.values[f.key] = value
  end
end

function SettingsScene:textinput(text)
  if self.tab ~= 1 then return end
  local f = FIELDS[self.focusIndex]
  local value = self.values[f.key]
  if #value >= f.max then return end

  local filtered
  if f.key == "serverPort" then
    filtered = text:gsub("%D", "")
  elseif f.key == "serverHost" then
    filtered = text:gsub("[^%w%.%-%:]", "")
  else
    filtered = text:gsub("[%c]", "")
  end
  if filtered == "" then return end

  value = value:sub(1, self.caret - 1) .. filtered .. value:sub(self.caret)
  value = value:sub(1, f.max)
  self.values[f.key] = value
  self.caret = math.min(#value + 1, self.caret + #filtered)
end

function SettingsScene:update(dt)
  local mx, my = View.mouse()
  self.hover = nil
  for i = 1, #TABS do
    if UI.hit(mx, my, 86 + (i - 1) * 112, 58, 104, 20) then self.hover = "tab" .. i end
  end

  if self.tab == 1 then
    for i, f in ipairs(FIELDS) do
      if UI.hit(mx, my, f.x, f.y, f.w, 26) then self.hover = "field" .. i end
    end
    if UI.hit(mx, my, 352, 108, 220, 24) then self.hover = "fullscreen" end
    if UI.hit(mx, my, 352, 144, 220, 24) then self.hover = "fps" end
    if UI.hit(mx, my, 352, 180, 220, 24) then self.hover = "shake" end
  elseif self.tab == 2 then
    for i = 1, #ACTIONS do
      if UI.hit(mx, my, 86, 104 + (i - 1) * 25, 420, 22) then self.hover = "bind" .. i end
    end
    if UI.hit(mx, my, 86, 274, 130, 25) then self.hover = "resetControls" end
  elseif self.tab == 3 then
    if UI.hit(mx, my, 86, 126, 360, 16) then self.hover = "master" end
    if UI.hit(mx, my, 86, 186, 360, 16) then self.hover = "effects" end
  end

  if UI.hit(mx, my, 86, 280, 108, 28) then self.hover = "back" end
  if UI.hit(mx, my, 208, 280, 108, 28) then self.hover = "save" end
  if UI.hit(mx, my, 330, 280, 108, 28) then self.hover = "reset" end

  if self.dragSlider and love.mouse.isDown(1) then
    self:setSlider(self.dragSlider, mx)
  elseif self.dragSlider then
    self.dragSlider = nil
    Settings.save()
  end
end

function SettingsScene:drawBackground()
  Sky.draw()
  love.graphics.setColor(0.015, 0.025, 0.025, 0.35)
  love.graphics.rectangle("fill", 0, 0, 640, 360)
end

function SettingsScene:drawToggle(x, y, label, value, hovered)
  UI.set(hovered and UI.C.cream or UI.C.cream2)
  love.graphics.setFont(UI.font(11))
  love.graphics.print(label, x, y)
  love.graphics.setFont(UI.font(11, true))
  UI.set(value and UI.C.green or UI.C.red)
  love.graphics.printf(value and "ON" or "OFF", x, y, 220, "right")
  UI.set(UI.C.ink3)
  love.graphics.rectangle("fill", x, y + 17, 220, 1)
end

function SettingsScene:drawSlider(x, y, label, key)
  UI.small(label, x, y - 18, UI.C.cream2, "left")
  UI.set(UI.C.ink3)
  love.graphics.rectangle("fill", x, y, 360, 6)
  UI.set(UI.C.orange)
  love.graphics.rectangle("fill", x, y, 360 * (Settings.data[key] or 0), 6)
  UI.set(UI.C.cream)
  love.graphics.circle("fill", x + 360 * (Settings.data[key] or 0), y + 3, 4)
  UI.small(string.format("%d%%", math.floor((Settings.data[key] or 0) * 100)),
    x, y + 9, UI.C.cream, "right", 360)
end

function SettingsScene:drawGame()
  UI.small("PILOT + NETWORK", 86, 84, UI.C.orange, "left")
  UI.small("DISPLAY", 352, 84, UI.C.orange, "left")

  for i, f in ipairs(FIELDS) do
    UI.textField(f.x, f.y, f.w, 26, f.label, self.values[f.key], self.focusIndex == i, self.caret)
  end

  self:drawToggle(352, 108, "FULLSCREEN", Settings.data.fullscreen == true, self.hover == "fullscreen")
  self:drawToggle(352, 144, "SHOW FPS", Settings.data.showFps == true, self.hover == "fps")
  self:drawToggle(352, 180, "SCREEN SHAKE", Settings.data.screenShake ~= false, self.hover == "shake")

  UI.small("Ubuntu server address or IP. TCP port must match the server.", 86, 250, UI.C.cream2, "left")
  UI.small("SETTINGS SAVE TO", 352, 214, UI.C.cream2, "left")
  UI.small("settings.json", 352, 226, UI.C.cream, "left")
end

function SettingsScene:drawControls()
  UI.small("CLICK A CONTROL, THEN PRESS A KEY.", 86, 84, UI.C.cream2, "left", 480)
  for i, action in ipairs(ACTIONS) do
    local y = 104 + (i - 1) * 25
    UI.set(self.hover == "bind" .. i and UI.C.cream or UI.C.cream2)
    love.graphics.setFont(UI.font(8))
    love.graphics.print(action.label, 94, y + 6)
    local selected = self.awaitBind == action.key
    UI.set(selected and UI.C.orange or UI.C.ink3)
    love.graphics.rectangle("fill", 390, y, 116, 22)
    UI.set(selected and UI.C.cream or UI.C.orange)
    love.graphics.setFont(UI.font(8, true))
    love.graphics.printf(selected and "PRESS KEY" or Controls.label(action.key),
      390, y + 6, 116, "center")
  end
  UI.button(86, 274, 130, 25, "RESET CONTROLS", {
    hover = self.hover == "resetControls", font = UI.font(7, true),
  })
end

function SettingsScene:drawAudio()
  UI.small("MASTER VOLUME", 86, 84, UI.C.orange, "left")
  self:drawSlider(86, 126, "MASTER", "masterVolume")
  self:drawSlider(86, 186, "EFFECTS + ENGINES", "effectsVolume")
  UI.small("AUDIO APPLIES TO GUNS, ENGINES, IMPACTS AND EXPLOSIONS.",
    86, 238, UI.C.cream2, "left", 440)
end

function SettingsScene:draw()
  self:drawBackground()
  UI.panel(56, 28, 528, 304)
  UI.title("SETTINGS", 38, 24)

  for i, name in ipairs(TABS) do
    UI.button(86 + (i - 1) * 112, 58, 104, 20, name, {
      hover = self.hover == "tab" .. i,
      selected = self.tab == i,
      font = UI.font(7, true),
    })
  end

  if self.tab == 1 then
    self:drawGame()
  elseif self.tab == 2 then
    self:drawControls()
  else
    self:drawAudio()
  end

  if self.status then
    UI.small(self.status:sub(1, 40), 86, 264, UI.C.green, "left", 240)
  end

  UI.button(86, 280, 108, 28, "BACK", {
    hover = self.hover == "back", font = UI.font(9, true),
  })
  UI.button(208, 280, 108, 28, "SAVE", {
    hover = self.hover == "save", font = UI.font(9, true),
  })
  UI.button(330, 280, 108, 28, "RESET", {
    hover = self.hover == "reset", font = UI.font(9, true),
  })
end

function SettingsScene:mousepressed(x, y)
  local mx, my = View.toVirtual(x, y)
  for i = 1, #TABS do
    if UI.hit(mx, my, 86 + (i - 1) * 112, 58, 104, 20) then
      self.tab = i
      self.awaitBind = nil
      self.dragSlider = nil
      return
    end
  end

  if self.tab == 1 then
    for i, f in ipairs(FIELDS) do
      if UI.hit(mx, my, f.x, f.y, f.w, 26) then
        self:focusField(i)
        return
      end
    end
    if UI.hit(mx, my, 352, 108, 220, 24) then
      self:setFullscreen(not Settings.data.fullscreen)
    elseif UI.hit(mx, my, 352, 144, 220, 24) then
      Settings.data.showFps = not Settings.data.showFps
      Settings.save()
    elseif UI.hit(mx, my, 352, 180, 220, 24) then
      Settings.data.screenShake = not Settings.data.screenShake
      Settings.save()
    end
  elseif self.tab == 2 then
    for i, action in ipairs(ACTIONS) do
      if UI.hit(mx, my, 86, 104 + (i - 1) * 25, 420, 22) then
        self.awaitBind = action.key
        return
      end
    end
    if UI.hit(mx, my, 86, 274, 130, 25) then
      Controls.reset()
      self.status = "CONTROLS RESET."
    end
  elseif self.tab == 3 then
    if UI.hit(mx, my, 86, 126, 360, 16) then
      self.dragSlider = "masterVolume"
      self:setSlider("masterVolume", mx)
    elseif UI.hit(mx, my, 86, 186, 360, 16) then
      self.dragSlider = "effectsVolume"
      self:setSlider("effectsVolume", mx)
    end
  end

  if UI.hit(mx, my, 86, 280, 108, 28) then
    self:save()
    App:pop()
  elseif UI.hit(mx, my, 208, 280, 108, 28) then
    self:save()
  elseif UI.hit(mx, my, 330, 280, 108, 28) then
    Settings.reset()
    self.values = {
      callsign = Settings.data.callsign,
      serverHost = Settings.data.serverHost,
      serverPort = tostring(Settings.data.serverPort),
    }
    self.focusIndex = 1
    self.caret = #self.values.callsign + 1
    self.awaitBind = nil
    self.dragSlider = nil
    Settings.apply()
    self.status = "DEFAULTS RESTORED."
  end
end

function SettingsScene:leave()
  Settings.save()
end

return SettingsScene
