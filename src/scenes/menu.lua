-- menu.lua
-- Title screen: solo test flight and multiplayer, with settings/quit below.

local App = require("src.app")
local C = require("shared.constants")
local Settings = require("src.game.settings")
local Sky = require("src.game.sky")
local Sprites = require("src.game.sprites")
local View = require("src.game.view")
local UI = require("src.ui.ui")
local log = require("src.core.log")

local Menu = { name = "menu", module = "src.scenes.menu" }

local function fakePlane(x, y, angle, team)
  return {
    x = x, y = y, angle = angle, throttle = 0.8, alive = true,
    invuln = 0, hitFlash = 0, parts = { engine = 60, wing = 60, tail = 60, guns = 60 },
    team = team,
  }
end

function Menu:enter()
  self.time = 0
  self.selected = 1
  self.hover = nil
  self.decorClouds = {
    { x = 470, y = 84, r = 26, alpha = 0.50, variant = 1, speed = 3 },
    { x = 552, y = 150, r = 34, alpha = 0.48, variant = 2, speed = -2 },
    { x = 300, y = 168, r = 18, alpha = 0.35, variant = 3, speed = 4 },
    { x = 610, y = 50, r = 22, alpha = 0.45, variant = 1, speed = 2 },
    { x = 76, y = 300, r = 26, alpha = 0.28, variant = 2, speed = -3 },
  }
  self.planeA = fakePlane(90, 146, -0.06, 1)
  self.planeB = fakePlane(560, 176, math.pi + 0.05, 2)
  log.info("menu entered")
end

function Menu:update(dt)
  self.time = self.time + dt
  for _, cloud in ipairs(self.decorClouds) do
    cloud.x = cloud.x + cloud.speed * dt
    if cloud.x < -50 then cloud.x = 690 elseif cloud.x > 690 then cloud.x = -50 end
  end

  self.planeA.x = (self.planeA.x + 34 * dt)
  if self.planeA.x > 700 then self.planeA.x = -60 end
  self.planeA.y = 146 + math.sin(self.time * 0.7) * 8
  self.planeB.x = (self.planeB.x - 26 * dt)
  if self.planeB.x < -60 then self.planeB.x = 700 end
  self.planeB.y = 176 + math.sin(self.time * 0.55 + 2) * 7

  local mx, my = View.mouse()
  self.hover = nil
  if UI.hit(mx, my, 36, 198, 270, 78) then
    self.hover = 1
  elseif UI.hit(mx, my, 334, 198, 270, 78) then
    self.hover = 2
  elseif UI.hit(mx, my, 486, 316, 118, 20) then
    self.hover = 3
  elseif UI.hit(mx, my, 36, 316, 90, 20) then
    self.hover = 4
  end
end

function Menu:drawSky()
  Sky.draw()

  local function ridge(base, amp, phase, color)
    local points = { 0, 360 }
    for x = 0, 640, 16 do
      local y = base + math.sin(x * 0.017 + phase) * amp
        + math.sin(x * 0.041 + phase * 2) * amp * 0.35
      points[#points + 1] = x
      points[#points + 1] = math.floor(y)
    end
    points[#points + 1] = 640
    points[#points + 1] = 360
    love.graphics.setColor(color[1], color[2], color[3], 1)
    love.graphics.polygon("fill", points)
  end

  ridge(288, 17, 0.4, { 0.165, 0.265, 0.265 })
  ridge(316, 12, 2.1, { 0.100, 0.180, 0.190 })
  ridge(338, 8, 4.2, { 0.050, 0.105, 0.115 })
  love.graphics.setColor(0.030, 0.060, 0.065, 1)
  love.graphics.rectangle("fill", 0, 350, 640, 10)
end

function Menu:draw()
  self:drawSky()

  for _, cloud in ipairs(self.decorClouds) do
    Sprites.drawCloud(cloud, 0, 0, 1.0)
  end

  Sprites.drawPlane(self.planeA, self.time, { colors = Sprites.TEAM.player })
  Sprites.drawPlane(self.planeB, self.time, { colors = Sprites.TEAM.enemy })

  -- masthead, left aligned like a squadron board
  love.graphics.setFont(UI.font(30, true))
  UI.set(UI.C.cream)
  love.graphics.print("YUGOSLAVIAN", 36, 26)
  love.graphics.setFont(UI.font(16, true))
  UI.set(UI.C.orange)
  love.graphics.print("WAR", 36, 58)
  UI.set(UI.C.orange)
  love.graphics.rectangle("fill", 36, 82, 278, 2)
  love.graphics.setFont(UI.font(8))
  UI.set(UI.C.cream2)
  love.graphics.print("ADRIATIC AIR COMBAT / 1941", 36, 90)
  love.graphics.print("2-4 PILOTS  /  ROOMS  /  SPECTATORS", 36, 110)

  UI.card(36, 198, 270, 78, "01", "SOLO TEST FLIGHT", "DEMO PLANE / FREE FLIGHT",
    self.selected == 1, self.hover == 1)
  UI.card(334, 198, 270, 78, "02", "MULTIPLAYER", "OPEN ROOMS / 2-4 PLAYERS",
    self.selected == 2, self.hover == 2)

  UI.button(486, 316, 118, 20, "SETTINGS", {
    hover = self.hover == 3, font = UI.font(8, true),
  })
  UI.button(36, 316, 90, 20, "QUIT", {
    hover = self.hover == 4, font = UI.font(8, true),
  })

  UI.small("ENTER SELECT   /   LEFT RIGHT   /   F1 DEBUG   /   F2 CONSOLE", 140, 342,
    UI.C.cream2, "left")
  UI.small("V" .. C.VERSION, 580, 342, UI.C.cream2, "right")
end

function Menu:activate(index)
  if index == 1 then
    App:push(require("src.scenes.solo"))
  elseif index == 2 then
    App:push(require("src.scenes.multiplayer"))
  elseif index == 3 then
    App:push(require("src.scenes.settings"))
  elseif index == 4 then
    love.event.quit(0)
  end
end

function Menu:keypressed(key)
  if key == "left" or key == "a" then
    self.selected = 1
  elseif key == "right" or key == "d" then
    self.selected = 2
  elseif key == "return" or key == "kpenter" or key == "space" then
    self:activate(self.selected)
  elseif key == "s" then
    self:activate(3)
  elseif key == "q" then
    love.event.quit(0)
  elseif key == "escape" then
    love.event.quit(0)
  end
end

function Menu:mousepressed(x, y)
  local mx, my = View.toVirtual(x, y)
  if UI.hit(mx, my, 36, 198, 270, 78) then
    self:activate(1)
  elseif UI.hit(mx, my, 334, 198, 270, 78) then
    self:activate(2)
  elseif UI.hit(mx, my, 486, 316, 118, 20) then
    self:activate(3)
  elseif UI.hit(mx, my, 36, 316, 90, 20) then
    self:activate(4)
  end
end

return Menu
