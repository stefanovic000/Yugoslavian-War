-- solo.lua
-- Test flight against a demo AI plane. This is a full simulation of the same
-- shared flight/combat model used online: wrap-around arena, clouds, modular
-- damage, parachute ammo and stalling.

local App = require("src.app")
local C = require("shared.constants")
local Clouds = require("shared.clouds")
local Flight = require("shared.flight")
local M = require("shared.mathx")
local Sim = require("shared.sim")
local AI = require("shared.ai")
local Debug = require("src.core.debug")
local dd = require("src.core.debugdraw")
local Settings = require("src.game.settings")
local Sky = require("src.game.sky")
local Sprites = require("src.game.sprites")
local Ground = require("src.game.ground")
local Walls = require("src.game.walls")
local Camera = require("src.game.camera")
local Vision = require("shared.vision")
local VisionOverlay = require("src.game.visionoverlay")
local Audio = require("src.game.audio")
local Particles = require("src.game.particles")
local View = require("src.game.view")
local UI = require("src.ui.ui")
local Combat = require("shared.combat")
local log = require("src.core.log")

local Solo = { name = "solo", module = "src.scenes.solo" }

local W, H = C.WORLD.w, C.WORLD.h

local function damp(a, b, lambda, dt)
  return a + (b - a) * (1 - math.exp(-lambda * dt))
end

local function covered(clouds, plane)
  local samples = {
    { 0, 0 }, { 15, 0 }, { -14, 0 }, { 0, -5 }, { 0, 5 }, { 8, -3 }, { -8, 3 },
  }
  for _, s in ipairs(samples) do
    local x, y = Combat.toWorld(plane, s[1], s[2])
    if Clouds.pointInside(clouds, x, y) then return true end
  end
  return false
end

local function spawnPoint(side)
  local y = M.clamp(120 + love.math.random() * 120, 80, C.WORLD.groundY - 80)
  if side == "left" then
    return C.WORLD.wallLeft + 60, y, 0
  end
  return C.WORLD.wallRight - 60, y, math.pi
end

function Solo:enter()
  self.seed = os.time() + math.floor(os.clock() * 1000)
  self.sim = Sim.new({ seed = self.seed })
  self.sim.pickupTimer = 4

  local px, py, pa = spawnPoint("left")
  self.player = self.sim:addPlane({
    id = 1, x = px, y = py, angle = pa, speed = 120, throttle = 0.7,
    name = Settings.data.callsign, team = 1,
  })
  self.enemy = self.sim:addPlane({
    id = 2, x = C.WORLD.wallRight - 60, y = M.clamp(py + 40, 80, C.WORLD.groundY - 80),
    angle = math.pi, speed = 120, throttle = 0.8,
    name = "DEMO", team = 2, hp = 96,
  })
  self.aiState = AI.newState()
  self.particles = Particles.new(700)
  self.farClouds = Clouds.new(self.seed + 7, 7, { cluster = false })

  -- Keep the initial duel visible without tearing a cloud bank apart.
  Clouds.avoidPoints(self.sim.clouds, { self.player, self.enemy }, 75)

  self.input = { throttle = 0.65, pitch = 0, fire = false }
  self.aDown, self.dDown = false, false
  self.lastPitchKey = nil
  self.kills = 0
  self.score = 0
  self.playerRespawn = 0
  self.enemyRespawn = 0
  self.paused = false
  self.camera = Camera.new()
  self.enemyVisible = false
  self.revealEnemy = 0
  self.pauseIndex = 1
  self.hover = nil
  self.uiTime = 0
  self.hintTimer = 9
  self.notice = nil
  self.noticeTimer = 0
  self.flash = 0
  self.shake = 0
  self.hitMarker = 0
  self.hitX, self.hitY = 0, 0
  self.hullGhost = 1
  self.wasStalling = false
  self.partFlash = { engine = 0, wing = 0, tail = 0, guns = 0 }

  self:registerDebug()
  Camera.snap(self.camera, self.player.x, self.player.y)
  log.info("solo test flight entered (seed=%d)", self.seed)
end

function Solo:leave()
  Audio.stopEngines()
  Debug:removeCommands("solo")
  Debug:clearWatches("solo")
  log.info("solo test flight left")
end

function Solo:registerDebug()
  Debug:removeCommands("solo")
  Debug:clearWatches("solo")
  local S = self

  Debug:command("god", "Toggle player invulnerability", function()
    S.player.god = not S.player.god
    Debug:echo("god mode " .. (S.player.god and "ON" or "OFF"), "ok")
  end, { ns = "solo" })

  Debug:command("ammo", "Set player ammo", function(args)
    local n = tonumber(args[1]) or 120
    S.player.ammo = math.max(0, math.min(S.player.maxAmmo, math.floor(n)))
    Debug:echo("ammo = " .. S.player.ammo, "ok")
  end, { ns = "solo", usage = "ammo [amount]" })

  Debug:command("kill", "Destroy the demo plane", function()
    S:destroyEnemy()
    Debug:echo("demo plane destroyed", "ok")
  end, { ns = "solo" })

  Debug:command("spawn", "Drop an ammo crate", function()
    S.sim:spawnPickup()
    Debug:echo("ammo crate dropped", "ok")
  end, { ns = "solo" })

  Debug:command("tp", "Teleport the player", function(args)
    local x, y = tonumber(args[1]), tonumber(args[2])
    if not x or not y then Debug:echo("usage: tp <x> <y>", "error") return end
    S.player.x = M.wrap(x, W)
    S.player.y = M.wrap(y, H)
    Debug:echo(string.format("player at %.0f, %.0f", S.player.x, S.player.y), "ok")
  end, { ns = "solo", usage = "tp <x> <y>" })

  Debug:watch("player hp", function() return S.player.hp end, "solo")
  Debug:watch("speed", function() return math.floor(Flight.speed(S.player)) end, "solo")
  Debug:watch("throttle", function() return math.floor(S.player.throttle * 100) end, "solo")
  Debug:watch("ammo", function() return S.player.ammo end, "solo")
  Debug:watch("stalling", function() return S.player.stalling end, "solo")
  Debug:watch("demo hp", function() return S.enemy.hp end, "solo")
  Debug:watch("particles", function() return S.particles:count() end, "solo")
end

function Solo:inputForPlayer(dt)
  local p = self.player
  if not p.alive then
    self.aDown, self.dDown = false, false
    self.lastPitchKey = nil
    return { throttle = p.throttle, pitch = 0, fire = false }
  end

  local up = love.keyboard.isDown("w") or love.keyboard.isDown("up")
  local down = love.keyboard.isDown("s") or love.keyboard.isDown("down")
  if up and not down then
    self.input.throttle = math.min(1, self.input.throttle + 1.2 * dt)
  elseif down and not up then
    self.input.throttle = math.max(0, self.input.throttle - 1.2 * dt)
  end

  -- A/D are plane-relative: A always rotates counter-clockwise, D clockwise.
  -- Facing right that is A=up/D=down; facing left it is D=up/A=down.
  -- The newest pressed direction stays active until it is released.
  local a = love.keyboard.isDown("a") or love.keyboard.isDown("left")
  local d = love.keyboard.isDown("d") or love.keyboard.isDown("right")
  if a and not self.aDown then self.lastPitchKey = "a" end
  if d and not self.dDown then self.lastPitchKey = "d" end
  if self.lastPitchKey == "a" and not a then self.lastPitchKey = nil end
  if self.lastPitchKey == "d" and not d then self.lastPitchKey = nil end
  self.aDown, self.dDown = a, d

  local pitch = 0
  if self.lastPitchKey == "a" then
    pitch = -1
  elseif self.lastPitchKey == "d" then
    pitch = 1
  end
  self.input.pitch = pitch
  self.input.fire = love.keyboard.isDown("space")
  return self.input
end

function Solo:handleEvents(events)
  for _, e in ipairs(events) do
    if e.type == "shot" then
      if e.owner == self.enemy.id and self.player.alive and self.enemy.alive then
        local dist = M.dist(self.player.x, self.player.y, self.enemy.x, self.enemy.y)
        if dist <= C.VISION.revealRange
          and Vision.lineOfSight(self.player, self.enemy, self.sim.clouds) then
          self.revealEnemy = C.VISION.revealTime
        end
      end
      local inCloud = Clouds.pointInside(self.sim.clouds, e.x, e.y)
      Audio.play("shot", e.owner == 1 and 0.20 or 0.10)
      if not inCloud then
        self.particles:muzzle(e.x, e.y, e.angle, e.owner == 1 and { 0.55, 0.95, 0.95 } or { 1, 0.7, 0.3 })
      end
      if e.owner == 1 then self.shake = math.max(self.shake, 0.4) end
    elseif e.type == "hit" then
      Audio.play("hit", e.victim == 1 and 0.30 or 0.20)
      self.particles:hit(e.x, e.y, 0, e.victim == 1 and { 1, 0.4, 0.3 } or { 1, 0.8, 0.4 })
      if e.owner == 1 then
        self.hitMarker = 0.18
        self.hitX, self.hitY = e.x, e.y
      end
      if e.victim == 1 then
        self.flash = 0.36
        self.shake = math.max(self.shake, 6)
        self.partFlash[e.part] = 0.30
      end
    elseif e.type == "kill" then
      Audio.play("explosion", e.victim == 1 and 0.55 or 0.65)
      local color = e.victim == 1 and { 0.45, 0.85, 1 } or { 1, 0.45, 0.25 }
      self.particles:explosion(e.x, e.y, color, e.victim == 1 and 1.5 or 1.0)
      if e.victim == 1 then
        self.playerRespawn = C.PLANE.respawnTime
        self.shake = math.max(self.shake, 9)
        self.flash = 0.55
        self.notice = "SHOT DOWN / RESPAWNING"
        self.noticeTimer = 2.5
      elseif e.victim == self.enemy.id then
        self.enemyRespawn = 4
        self.kills = self.kills + 1
        self.score = self.score + 100
        self.notice = "DEMO PLANE DOWN  +100"
        self.noticeTimer = 2.2
        self.shake = math.max(self.shake, 5)
      end
    elseif e.type == "crash" then
      Audio.play("explosion", 0.7)
      self.particles:explosion(e.x, e.y, { 0.95, 0.58, 0.25 }, e.victim == 1 and 1.4 or 1)
      self.shake = math.max(self.shake, 7)
      if e.victim == 1 then
        self.playerRespawn = C.PLANE.respawnTime
        self.flash = 0.45
        self.notice = "CRASHED / RESPAWNING"
        self.noticeTimer = 2.2
      elseif e.victim == self.enemy.id then
        self.enemyRespawn = 4
        self.notice = "DEMO PLANE CRASHED"
        self.noticeTimer = 1.8
      end
    elseif e.type == "pickup" then
      Audio.play("pickup", e.player == 1 and 0.24 or 0.10)
      if e.player == 1 then
        self.notice = "AMMO +" .. tostring(e.ammo)
        self.noticeTimer = 1.6
        self.particles:flash(e.x, e.y, 5, 0.15, { 1, 0.85, 0.4 })
      end
    elseif e.type == "ram" then
      Audio.play("ram", 0.35)
      self.shake = math.max(self.shake, 5)
      self.particles:flash(e.x, e.y, 6, 0.12, { 1, 0.8, 0.4 })
    elseif e.type == "overheat" then
      Audio.play("overheat", e.player == 1 and 0.42 or 0.16)
      if e.player == 1 then
        self.notice = "GUNS JAMMED"
        self.noticeTimer = 1.6
        self.shake = math.max(self.shake, 2)
      end
    end
  end
end

function Solo:destroyEnemy()
  if not self.enemy.alive then return end
  self.enemy.alive = false
  self.enemy.hp = 0
  self.particles:explosion(self.enemy.x, self.enemy.y, { 1, 0.45, 0.25 }, 1)
  self.enemyRespawn = 4
  self.kills = self.kills + 1
  self.score = self.score + 100
  self.notice = "DEMO PLANE DOWN  +100"
  self.noticeTimer = 2.2
end

function Solo:respawnPlayer()
  local px, py, pa = spawnPoint(love.math.random() < 0.5 and "left" or "right")
  Flight.reset(self.player, px, py, pa)
  self.playerRespawn = 0
  self.input.throttle = 0.65
  self.hullGhost = 1
  self.aDown, self.dDown = false, false
  self.lastPitchKey = nil
  self.wasStalling = false
  Camera.snap(self.camera, self.player.x, self.player.y)
end

function Solo:respawnEnemy()
  local px, py, pa = spawnPoint(love.math.random() < 0.5 and "left" or "right")
  Flight.reset(self.enemy, px, py, pa)
  self.enemyRespawn = 0
  self.aiState = AI.newState()
end

function Solo:fixedUpdate(dt)
  if self.paused then return end

  if self.player.alive then
    self:inputForPlayer(dt)
  else
    self.input.fire = false
    self.input.pitch = 0
  end

  Clouds.update(self.farClouds, dt)

  if self.playerRespawn > 0 then
    self.playerRespawn = self.playerRespawn - dt
    if self.playerRespawn <= 0 then self:respawnPlayer() end
  end

  if self.enemyRespawn > 0 then
    self.enemyRespawn = self.enemyRespawn - dt
    if self.enemyRespawn <= 0 then self:respawnEnemy() end
  end

  local aiInput = { throttle = 0, pitch = 0, fire = false }
  if self.enemy.alive then
    local target = self.player.alive and self.player or nil
    aiInput = AI.input(self.enemy, target, self.sim, self.aiState, dt)
  end

  local events = self.sim:step({
    [1] = self.input,
    [2] = aiInput,
  }, dt)

  self:handleEvents(events)

  self.particles:update(dt)

  if self.player.alive and self.player.parts.engine < 35 and love.math.random() < 0.55 then
    self.particles:smoke(self.player.x, self.player.y,
      (love.math.random() - 0.5) * 16, -22 - love.math.random() * 10,
      3 + love.math.random() * 3, 0.7, { 0.17, 0.17, 0.17 })
  end
  if self.player.alive and self.player.parts.wing < 25 and love.math.random() < 0.25 then
    self.particles:spark(self.player.x, self.player.y, math.pi * 0.5,
      30 + love.math.random() * 50, 0.35, { 1, 0.7, 0.3 })
  end

  if self.enemy.alive and self.enemy.parts.engine < 24 and love.math.random() < 0.8 then
    self.particles:smoke(self.enemy.x - math.cos(self.enemy.angle) * 14,
      self.enemy.y - math.sin(self.enemy.angle) * 14,
      (love.math.random() - 0.5) * 20, -20 - love.math.random() * 10,
      3 + love.math.random() * 3, 0.7, { 0.18, 0.18, 0.18 })
  end
end

function Solo:update(dt)
  self.uiTime = self.uiTime + dt
  self.hintTimer = math.max(0, self.hintTimer - dt)
  self.noticeTimer = math.max(0, self.noticeTimer - dt)
  self.flash = math.max(0, self.flash - dt * 2.2)
  self.shake = math.max(0, self.shake - dt * 18)
  self.hitMarker = math.max(0, self.hitMarker - dt)
  for k, v in pairs(self.partFlash) do
    self.partFlash[k] = math.max(0, v - dt)
  end
  self.hullGhost = damp(self.hullGhost, self.player.hp / self.player.maxHp, 4, dt)

  local follow = self.player.alive and self.player or (self.enemy.alive and self.enemy)
  if follow then Camera.follow(self.camera, follow.x, follow.y, dt) end

  self.revealEnemy = math.max(0, self.revealEnemy - dt)
  self.enemyVisible = self.player.alive and self.enemy.alive
    and Vision.canSee(self.player, self.enemy, self.sim.clouds)

  if self.enemy.alive and self.player.alive then
    Audio.setEngine("demo",
      self.enemy.x - self.player.x, self.enemy.y - self.player.y,
      self.enemy.throttle, true,
      Clouds.pointInside(self.sim.clouds, self.enemy.x, self.enemy.y))
  else
    Audio.setEngine("demo", 0, 0, 0, false)
  end

  if self.player.alive and self.player.stalling and not self.wasStalling then
    Audio.play("stall", 0.22)
  end
  self.wasStalling = self.player.stalling

  local mx, my = View.mouse()
  self.hover = nil
  if self.paused then
    if UI.hit(mx, my, 240, 158, 160, 26) then self.hover = 1 end
    if UI.hit(mx, my, 240, 190, 160, 26) then self.hover = 2 end
    if UI.hit(mx, my, 240, 222, 160, 26) then self.hover = 3 end
  end
end

function Solo:drawSky()
  Sky.draw()
end

function Solo:drawWorld()
  local ws = C.WORLD.scale or 1
  love.graphics.push()
  love.graphics.scale(ws, ws)
  Camera.apply(self.camera)

  for _, cloud in ipairs(self.farClouds.list) do
    Sprites.drawCloudCopies(cloud, 0.28)
  end

  local shakeX, shakeY = 0, 0
  if Settings.data.screenShake and self.shake > 0 then
    shakeX = (love.math.random() - 0.5) * self.shake
    shakeY = (love.math.random() - 0.5) * self.shake
  end

  love.graphics.push()
  love.graphics.translate(shakeX, shakeY)

  Walls.draw()
  Ground.draw()

  for _, b in ipairs(self.sim.bullets) do
    if b.x > C.WORLD.wallLeft and b.x < C.WORLD.wallRight
      and b.y > -10 and b.y < C.WORLD.groundY
      and not Clouds.pointInside(self.sim.clouds, b.x, b.y) then
      Sprites.drawBullet(b)
    end
  end

  for _, pickup in ipairs(self.sim.pickups) do
    Sprites.drawPickup(pickup, self.uiTime)
  end

  self.particles:draw()

  local playerHidden = self.player.alive and covered(self.sim.clouds, self.player)
  local reveal = (not self.enemyVisible) and self.revealEnemy > 0

  if self.enemy.alive and (self.enemyVisible or reveal) then
    Sprites.drawPlaneCopies(self.enemy, self.uiTime, {
      colors = Sprites.TEAM.enemy,
      alpha = reveal and 0.25 or 1,
    })
    if self.enemyVisible then
      love.graphics.setFont(UI.font(8))
      UI.set(UI.C.cream)
      local labelX = M.clamp(self.enemy.x - 30, C.WORLD.wallLeft, C.WORLD.wallRight - 60)
      local barX = M.clamp(self.enemy.x - 15, C.WORLD.wallLeft + 2, C.WORLD.wallRight - 32)
      love.graphics.printf("DEMO", labelX, self.enemy.y - 28, 60, "center")
      love.graphics.setColor(0.1, 0.12, 0.12, 0.7)
      love.graphics.rectangle("fill", barX, self.enemy.y - 19, 30, 3)
      love.graphics.setColor(0.95, 0.45, 0.30, 0.95)
      love.graphics.rectangle("fill", barX, self.enemy.y - 19,
        30 * (self.enemy.hp / self.enemy.maxHp), 3)
    end
  end

  if self.player.alive then
    Sprites.drawPlaneCopies(self.player, self.uiTime, { colors = Sprites.TEAM.player })
  end

  if dd.enabled then
    dd.grid(0, 0, W, H, 40, { 0.4, 0.5, 0.6, 0.10 })
    for _, plane in ipairs({ self.player, self.enemy }) do
      if plane.alive then
        local shapes = Combat.SHAPES
        for _, s in ipairs(shapes) do
          local x, y = Combat.toWorld(plane, s.x, s.y)
          dd.circle(x, y, s.r, s.part == "wing" and UI.C.orange or UI.C.teal, 12)
        end
        dd.vector(plane.x, plane.y, plane.vx * 0.2, plane.vy * 0.2, UI.C.green, 1)
      end
    end
    for _, cloud in ipairs(self.sim.clouds.list) do
      for _, puff in ipairs(cloud.puffs) do
        dd.circle(cloud.x + puff.dx, cloud.y + puff.dy, puff.r, UI.C.cream2, 16)
      end
    end
  end

  if self.hitMarker > 0 then
    local a = math.min(1, self.hitMarker / 0.18)
    love.graphics.setColor(1, 0.94, 0.72, a)
    love.graphics.setLineWidth(1)
    love.graphics.line(self.hitX - 4, self.hitY - 4, self.hitX + 4, self.hitY + 4)
    love.graphics.line(self.hitX + 4, self.hitY - 4, self.hitX - 4, self.hitY + 4)
  end

  love.graphics.pop()

  -- clouds cover planes, but the local player stays visible as a ghost so you
  -- can still fly while hidden from everyone else.
  for _, cloud in ipairs(self.sim.clouds.list) do
    Sprites.drawCloudCopies(cloud, 1)
  end

  if playerHidden then
    Sprites.drawPlaneCopies(self.player, self.uiTime, { colors = Sprites.TEAM.player, alpha = 0.55 })
  end

  love.graphics.pop()
end

function Solo:drawHud()
  local p = self.player

  -- hull + modules
  UI.panel(8, 8, 176, 54, { color = { 0.04, 0.06, 0.07, 0.72 }, border = UI.C.ink3 })
  love.graphics.setFont(UI.font(8))
  UI.set(UI.C.cream2)
  love.graphics.print("HULL", 16, 14)
  love.graphics.setColor(0.10, 0.12, 0.13, 0.9)
  love.graphics.rectangle("fill", 16, 26, 160, 7)
  local hpFrac = p.hp / p.maxHp
  if self.hullGhost > hpFrac then
    love.graphics.setColor(1.0, 0.52, 0.24, 0.85)
    love.graphics.rectangle("fill", 16 + 160 * hpFrac, 26, 160 * (self.hullGhost - hpFrac), 7)
  end
  local hpColor = hpFrac > 0.5 and UI.C.green or (hpFrac > 0.25 and UI.C.orange or UI.C.red)
  love.graphics.setColor(hpColor[1], hpColor[2], hpColor[3], 1)
  love.graphics.rectangle("fill", 16, 26, 160 * hpFrac, 7)
  UI.set(UI.C.cream)
  love.graphics.setFont(UI.font(9, true))
  love.graphics.printf(tostring(math.ceil(p.hp)), 16, 25, 160, "right")

  local parts = {
    { "ENG", p.parts.engine, "engine" }, { "WING", p.parts.wing, "wing" },
    { "TAIL", p.parts.tail, "tail" }, { "GUN", p.parts.guns, "guns" },
  }
  for i, part in ipairs(parts) do
    local x = 16 + (i - 1) * 40
    local frac = part[2] / C.PLANE.partHp
    UI.set(UI.C.cream2)
    love.graphics.setFont(UI.font(7))
    love.graphics.print(part[1], x, 40)
    love.graphics.setColor(0.10, 0.12, 0.13, 0.9)
    love.graphics.rectangle("fill", x, 49, 34, 3)
    local col = frac > 0.5 and UI.C.green or (frac > 0.2 and UI.C.orange or UI.C.red)
    love.graphics.setColor(col[1], col[2], col[3], 1)
    love.graphics.rectangle("fill", x, 49, 34 * frac, 3)
    if (self.partFlash[part[3]] or 0) > 0 then
      love.graphics.setColor(1, 1, 1, 0.55)
      love.graphics.rectangle("fill", x, 49, 34, 3)
    end
  end

  -- score
  UI.set(UI.C.cream)
  love.graphics.setFont(UI.font(14, true))
  love.graphics.printf("KILLS " .. string.format("%02d", self.kills), 0, 12, 632, "right")

  -- throttle + speed
  UI.panel(8, 312, 170, 40, { color = { 0.04, 0.06, 0.07, 0.72 }, border = UI.C.ink3 })
  love.graphics.setFont(UI.font(8))
  UI.set(UI.C.cream2)
  love.graphics.print(string.format("THR %d%%", math.floor(p.throttle * 100)), 16, 318)
  love.graphics.setColor(0.10, 0.12, 0.13, 0.9)
  love.graphics.rectangle("fill", 16, 330, 76, 6)
  love.graphics.setColor(UI.C.teal[1], UI.C.teal[2], UI.C.teal[3], 1)
  love.graphics.rectangle("fill", 16, 330, 76 * p.throttle, 6)
  love.graphics.setFont(UI.font(9, true))
  UI.set(UI.C.cream)
  love.graphics.printf(string.format("%03d", math.floor(Flight.speed(p))), 96, 318, 74, "right")
  love.graphics.setFont(UI.font(7))
  UI.set(UI.C.cream2)
  love.graphics.printf("SPEED", 96, 330, 74, "right")

  -- ammo
  UI.panel(512, 312, 120, 40, { color = { 0.04, 0.06, 0.07, 0.72 }, border = UI.C.ink3 })
  love.graphics.setFont(UI.font(8))
  UI.set(UI.C.cream2)
  love.graphics.print("AMMO", 520, 318)
  love.graphics.setFont(UI.font(14, true))
  UI.set(p.ammo > 0 and UI.C.cream or UI.C.red)
  love.graphics.printf(tostring(p.ammo), 520, 326, 104, "right")
  love.graphics.setFont(UI.font(6))
  if (p.jammed or 0) > 0 then
    UI.set(UI.C.red)
    love.graphics.print(string.format("JAM %.1f", p.jammed), 520, 340)
  else
    UI.set(UI.C.cream2)
    love.graphics.print("HEAT", 520, 340)
  end
  UI.heat(556, 343, 68, 4, p.heat or 0, p.jammed or 0)

  -- warnings
  local blink = math.floor(self.uiTime * 6) % 2 == 0
  if p.stalling and p.alive and blink then
    love.graphics.setFont(UI.font(16, true))
    UI.set(UI.C.red)
    love.graphics.printf("STALL", 0, 132, 640, "center")
    love.graphics.setFont(UI.font(8))
    UI.set(UI.C.cream2)
    love.graphics.printf("NOSE DOWN  /  FULL THROTTLE", 0, 152, 640, "center")
  end

  if p.alive and covered(self.sim.clouds, p) then
    love.graphics.setFont(UI.font(9, true))
    UI.set(UI.C.teal)
    love.graphics.printf("CLOUD COVER", 0, 172, 640, "center")
  end

  if not p.alive then
    love.graphics.setFont(UI.font(16, true))
    UI.set(UI.C.red)
    love.graphics.printf("WRECKED", 0, 140, 640, "center")
    love.graphics.setFont(UI.font(9))
    UI.set(UI.C.cream2)
    love.graphics.printf(string.format("RESPAWN IN %.1f", math.max(0, self.playerRespawn)), 0, 164, 640, "center")
  end

  if self.noticeTimer > 0 and self.notice then
    local alpha = math.min(1, self.noticeTimer * 2)
    love.graphics.setFont(UI.font(10, true))
    love.graphics.setColor(UI.C.cream[1], UI.C.cream[2], UI.C.cream[3], alpha)
    love.graphics.printf(self.notice, 0, 190, 640, "center")
  end

  if self.hintTimer > 0 and not self.paused then
    local alpha = math.min(1, self.hintTimer / 2)
    love.graphics.setColor(0.03, 0.05, 0.06, 0.65 * alpha)
    love.graphics.rectangle("fill", 154, 288, 332, 18)
    love.graphics.setFont(UI.font(8))
    love.graphics.setColor(UI.C.cream[1], UI.C.cream[2], UI.C.cream[3], alpha)
    love.graphics.printf("W/S THROTTLE   /   A/D PITCH   /   SPACE FIRE   /   ESC PAUSE", 154, 293, 332, "center")
  end

  if Settings.data.showFps then
    love.graphics.setFont(UI.font(8))
    UI.set(UI.C.cream2)
    love.graphics.print(string.format("%d FPS", Debug.fps), 304, 10)
  end

  if self.flash > 0 then
    love.graphics.setColor(0.85, 0.12, 0.10, self.flash * 0.35)
    love.graphics.rectangle("fill", 0, 0, 640, 360)
  end

  if p.hp / p.maxHp < 0.3 and p.alive then
    local a = 0.12 + math.sin(self.uiTime * 8) * 0.06
    love.graphics.setColor(0.8, 0.1, 0.1, a)
    love.graphics.setLineWidth(4)
    love.graphics.rectangle("line", 2, 2, 636, 356)
    love.graphics.setLineWidth(1)
  end
end

function Solo:drawPause()
  UI.screenDim(0.66)
  UI.panel(214, 100, 212, 170)
  UI.title("PAUSED", 112, 22)
  local labels = { "RESUME", "SETTINGS", "LEAVE FLIGHT" }
  for i, label in ipairs(labels) do
    UI.button(240, 158 + (i - 1) * 32, 160, 26, label, {
      selected = self.pauseIndex == i,
      hover = self.hover == i,
      font = UI.font(10, true),
    })
  end
  UI.small("ESC resume  /  UP DOWN choose  /  ENTER select", 0, 252, UI.C.cream2, "center")
end

function Solo:draw()
  self:drawSky()
  self:drawWorld()
  if self.player.alive then VisionOverlay.draw(self.player, self.camera, self.sim.clouds) end
  self:drawHud()
  if self.paused then
    self:drawPause()
  end
end

function Solo:activatePause(index)
  if index == 1 then
    self.paused = false
  elseif index == 2 then
    App:push(require("src.scenes.settings"))
  elseif index == 3 then
    App:pop()
  end
end

function Solo:keypressed(key)
  if not self.paused then
    if key == "escape" then
      self.paused = true
      self.pauseIndex = 1
    end
    return
  end

  if key == "escape" then
    self.paused = false
  elseif key == "up" or key == "w" then
    self.pauseIndex = math.max(1, self.pauseIndex - 1)
  elseif key == "down" or key == "s" then
    self.pauseIndex = math.min(3, self.pauseIndex + 1)
  elseif key == "return" or key == "kpenter" or key == "space" then
    self:activatePause(self.pauseIndex)
  end
end

function Solo:mousepressed(x, y)
  if not self.paused then return end
  local mx, my = View.toVirtual(x, y)
  for i = 1, 3 do
    if UI.hit(mx, my, 240, 158 + (i - 1) * 32, 160, 26) then
      self:activatePause(i)
      return
    end
  end
end

return Solo



