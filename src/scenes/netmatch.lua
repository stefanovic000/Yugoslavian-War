-- netmatch.lua
-- Networked match view. Own plane is predicted locally and reconciled from
-- snapshots; remote planes are smoothed toward the latest authoritative state.

local App = require("src.app")
local C = require("shared.constants")
local Clouds = require("shared.clouds")
local Shapes = require("shared.cloud_shapes")
local Flight = require("shared.flight")
local M = require("shared.mathx")
local Settings = require("src.game.settings")
local Sky = require("src.game.sky")
local Sprites = require("src.game.sprites")
local Ground = require("src.game.ground")
local CloudShadows = require("src.game.cloudshadows")
local Walls = require("src.game.walls")
local Camera = require("src.game.camera")
local Vision = require("shared.vision")
local VisionOverlay = require("src.game.visionoverlay")
local Audio = require("src.game.audio")
local Controls = require("src.game.controls")
local Aircraft = require("shared.aircraft")
local CloudFx = require("src.game.cloudfx")
local PlaneArt = require("src.game.planeart")
local Particles = require("src.game.particles")
local View = require("src.game.view")
local UI = require("src.ui.ui")
local Debug = require("src.core.debug")
local dd = require("src.core.debugdraw")
local Combat = require("shared.combat")
local log = require("src.core.log")

local NetMatch = { name = "netmatch", module = "src.scenes.netmatch", restartBlocked = true }

local W, H = C.WORLD.w, C.WORLD.h

local function damp(a, b, lambda, dt)
  return a + (b - a) * (1 - math.exp(-lambda * dt))
end

local function copyServerPlane(target, sp)
  target.x, target.y = sp.x, sp.y
  target.vx, target.vy = sp.vx, sp.vy
  target.angle = sp.a
  target.pitchVel = sp.pv or 0
  target.hp = sp.hp
  if sp.maxHp then target.maxHp = sp.maxHp end
  if sp.planeType then
    target.planeType = sp.planeType
    target.spec = Aircraft.get(sp.planeType)
    target.radius = target.spec.stats.radius
  end
  target.alive = sp.alive
  target.throttle = sp.throttle
  target.ammo = sp.ammo
  target.heat = sp.heat or 0
  target.jammed = sp.jam or 0
  target.team = sp.team or target.team
  target.parts.engine = sp.parts.engine
  target.parts.wing = sp.parts.wing
  target.parts.tail = sp.parts.tail
  target.parts.guns = sp.parts.guns
end

function NetMatch:enter(client, startMsg)
  self.client = client
  self.selfId = client.selfId
  self.roomId = startMsg.roomId
  self.players = {}
  self.names = {}
  self.scores = {}
  self.visuals = {}
  self.snapshot = nil
  self.snapRecvAt = love.timer.getTime()
  self.input = { throttle = 0.7, pitch = 0, fire = false }
  self.seq = 0
  self.ack = 0
  self.history = {}
  self.localPlane = nil
  self.localHidden = false
  self.wasStalling = false
  self.camera = Camera.new()
  self.reveal = {}
  self.localBullets = {}
  self.localFireTimer = 0
  self.spectator = startMsg.spectator == true
  self.spectateId = nil
  self.leavePrompt = false
  self.promptChoice = 2
  self.hover = nil
  self.particles = Particles.new(700)
  self.cloudFx = CloudFx.new()
  self.chatOpen = false
  self.chatText = ""
  self.chatLog = {}
  self.chatTimer = 0
  self.debrisSeen = {}
  self.hitMarker = 0
  self.hitX, self.hitY = 0, 0
  self.flash = 0
  self.shake = 0
  self.hullGhost = 1
  self.partFlash = { engine = 0, wing = 0, tail = 0, guns = 0 }
  self.notice = nil
  self.noticeTimer = 0
  self.banner = nil
  self.bannerTimer = 0
  self.bannerDuration = 0
  self.champion = nil
  self.bestReplay = nil
  self.bestReplayScore = 0
  self.replayBuffer = {}
  self.replayHits = {}
  self.highlight = nil
  self.replayClock = 0
  self.roomState = nil
  self.phase = "round"
  self.round = 1
  self.timer = 0
  self.hintTimer = 8
  self.aDown, self.dDown = false, false
  self.lastPitchKey = nil
  self.uiTime = 0
  self.exited = false
  self.joinQueued = false

  self:applyStart(startMsg)
  self:registerDebug()
  log.info("netmatch entered (seed=%s, spectator=%s)", tostring(startMsg.seed), tostring(self.spectator))
end

function NetMatch:applyStart(msg)
  self.seed = msg.seed
  self.localBullets = {}
  self.localFireTimer = 0
  self.cloudCount = msg.cloudCount or C.CLOUDS.count
  self.clouds = Clouds.new(self.seed, self.cloudCount or C.CLOUDS.count)
  Clouds.avoidPoints(self.clouds, C.SPAWNS, 80)
  Clouds.avoidPoints(self.clouds, C.SPAWNS3, 80)
  self.farClouds = Clouds.new(self.seed + 7, 7, { cluster = false })
  if _G.DOGFIGHT and _G.DOGFIGHT.opts and _G.DOGFIGHT.opts.noclouds then
    self.clouds.list = {}
    self.farClouds.list = {}
  end
  self.players = msg.players or {}
  self.names = {}
  self.scores = {}
  for _, p in ipairs(self.players) do self.names[p.id] = p.name end
  self.spectator = msg.spectator == true
  self.snapshot = nil
  self.visuals = {}
  self.localPlane = nil
  self.localHidden = false
  self.wasStalling = false
  self.camera = Camera.new()
  self.reveal = {}
  self.spectateId = nil
  self.history = {}
  self.seq = 0
  self.ack = 0
  self.joinQueued = false
  self.champion = nil
  self.roomId = msg.roomId or self.roomId
  self.visualTargets = {}
  self.respawns = {}
  self.phase = "round"
  self.round = 1
  self.timer = 0
  self.hullGhost = 1
  self.aDown, self.dDown = false, false
  self.lastPitchKey = nil
  self.leavePrompt = false
  self.partFlash = { engine = 0, wing = 0, tail = 0, guns = 0 }
  self.hitMarker = 0

  -- Preserve the local room/status for the HUD.
end

function NetMatch:leave()
  Audio.stopEngines()
  Debug:removeCommands("netmatch")
  Debug:clearWatches("netmatch")
  log.info("netmatch left")
end

function NetMatch:registerDebug()
  Debug:removeCommands("netmatch")
  Debug:clearWatches("netmatch")
  local N = self
  Debug:watch("net phase", function() return N.phase or "-" end, "netmatch")
  Debug:watch("round", function() return N.round or 0 end, "netmatch")
  Debug:watch("input seq", function() return N.seq end, "netmatch")
  Debug:watch("acked seq", function() return N.ack end, "netmatch")
  Debug:watch("local hp", function() return N.localPlane and N.localPlane.hp or "-" end, "netmatch")
  Debug:watch("remote planes", function() return N.snapshot and #N.snapshot.planes or 0 end, "netmatch")
end

function NetMatch:setBanner(text, duration)
  self.banner = text
  self.bannerTimer = duration
  self.bannerDuration = duration
end

function NetMatch:handleMessage(msg)
  if msg.type == "snapshot" then
    self:onSnapshot(msg)
  elseif msg.type == "match_start" then
    self:applyStart(msg)
    if not self.spectator then
      self:setBanner("ROUND 1", 1.5)
    end
    self.client.matchActive = true
  elseif msg.type == "match_cancelled" then
    self.client.matchActive = false
    self.client.notice = msg.reason or "MATCH ENDED"
    self.exited = true
    App:pop()
  elseif msg.type == "joined_match" then
    self.joinQueued = true
    self.notice = "IN THE NEXT MATCH"
    self.noticeTimer = 3
  elseif msg.type == "room" then
    self.roomState = msg.room
  elseif msg.type == "chat" then
    self.chatLog[#self.chatLog + 1] = { name = msg.name or "PILOT", text = msg.text or "" }
    if #self.chatLog > 20 then table.remove(self.chatLog, 1) end
    self.chatTimer = 6
  elseif msg.type == "kicked" then
    self.client.matchActive = false
    self.client.notice = "KICKED: " .. tostring(msg.reason or "BY HOST")
    self.client.forceBrowser = true
    self.exited = true
    App:pop()
  elseif msg.type == "room_closed" then
    self.client.matchActive = false
    self.client.notice = msg.reason or "ROOM CLOSED"
    self.client.forceBrowser = true
    self.exited = true
    App:pop()
  elseif msg.type == "error" then
    self.notice = tostring(msg.message or "SERVER ERROR")
    self.noticeTimer = 3
    self.joinQueued = false
  end
end

local function debrisColor(part)
  if part == "wing" then return { 0.38, 0.42, 0.28 }
  elseif part == "tail" then return { 0.24, 0.27, 0.20 }
  elseif part == "guns" then return { 0.42, 0.42, 0.38 }
  elseif part == "engine" then return { 0.30, 0.24, 0.18 }
  end
  return { 0.34, 0.34, 0.30 }
end

function NetMatch:damageVisible(id)
  if id == self.selfId or self.spectator then return true end
  local v = self.visuals and self.visuals[id]
  if not v then return false end
  if v.seenBy then
    for _, viewer in ipairs(v.seenBy) do
      if viewer == self.selfId then return true end
    end
    return false
  end
  return not self.localPlane or Vision.canSee(self.localPlane, v, self.clouds)
end

function NetMatch:debrisDirection(e)
  local owner = self.visuals[e.owner]
  local victim = self.visuals[e.victim]
  if owner and victim then
    return math.atan2(victim.y - owner.y, victim.x - owner.x)
  end
  return love.math.random() * math.pi * 2
end

function NetMatch:throwDebris(e, part, count, speedMin, speedMax, sizeMin, sizeMax)
  local dir = self:debrisDirection(e)
  local color = debrisColor(part)
  for _ = 1, count do
    local a = dir + (love.math.random() - 0.5) * 2.0
    local sp = speedMin + love.math.random() * (speedMax - speedMin)
    self.particles:debris(e.x, e.y,
      math.cos(a) * sp, math.sin(a) * sp,
      sizeMin + love.math.random() * (sizeMax - sizeMin),
      0.35 + love.math.random() * 0.75, color)
  end
end

function NetMatch:spawnPartPanel(e, part)
  local v = self.visuals[e.victim]
  if not v then return end
  local points, color
  if part == "wing" then
    points = { -1, 0, -8, 3, -3, 5 }
    color = { 0.46, 0.48, 0.43 }
  elseif part == "tail" then
    points = { -1, 0, -7, -5, -3, -1 }
    color = { 0.34, 0.36, 0.31 }
  elseif part == "guns" then
    points = { 0, 0, 4, -1, 2, 2 }
    color = { 0.54, 0.55, 0.52 }
  else
    points = { 0, 0, 6, -2, 3, 3 }
    color = { 0.27, 0.25, 0.21 }
  end
  for _ = 1, 2 do
    local dir = self:debrisDirection(e)
    local a = dir + (love.math.random() - 0.5) * 1.5
    local sp = 35 + love.math.random() * 80
    self.particles:panel(e.x, e.y,
      math.cos(a) * sp, math.sin(a) * sp - 10,
      points, color, 1.2 + love.math.random() * 0.5,
      v.angle + (love.math.random() - 0.5) * 1.2,
      0.7 + love.math.random() * 0.5)
  end
end

function NetMatch:spawnWingSeparation(e, v)
  local wing = { 8, 1, 5, 5, -5, 5, -8, 2, -3, 1 }
  local dir = self:debrisDirection(e)
  self.particles:panel(e.x, e.y,
    math.cos(dir) * 32, math.sin(dir) * 32 - 12,
    wing, { 0.38, 0.41, 0.34 }, 1.9,
    v.angle, 1.15)
  for _ = 1, 2 do
    self.particles:cloudWisp(e.x, e.y,
      (love.math.random() - 0.5) * 24, -8 - love.math.random() * 16,
      4 + love.math.random() * 4, 0.55, { 0.42, 0.43, 0.40 })
  end
end

function NetMatch:spawnDamageDebris(e)
  if not e.victim or not self:damageVisible(e.victim) then return end
  local part = e.part or "engine"
  local v = self.visuals[e.victim]
  local hp = v and v.parts and v.parts[part] or 60

  -- A couple of fine metal streaks on every hit.
  self:throwDebris(e, part, 2, 35, 90, 0.7, 1.7)
  self.particles:cloudWisp(e.x, e.y,
    (love.math.random() - 0.5) * 24, (love.math.random() - 0.5) * 24,
    3 + love.math.random() * 3, 0.28 + love.math.random() * 0.18,
    { 0.48, 0.50, 0.47 })
  if part == "guns" then
    self.particles:spark(e.x, e.y, love.math.random() * math.pi * 2, 90, 0.12,
      { 1, 0.78, 0.38 })
  end

  local seen = self.debrisSeen[e.victim] or {}
  self.debrisSeen[e.victim] = seen
  local prev = seen[part] or 60
  local band = hp <= 0 and 0 or (hp <= 22 and 22 or (hp <= 45 and 45 or 60))
  if band < prev then
    seen[part] = band
    if part == "wing" and band == 22 then self:spawnWingSeparation(e, v) end
    if band > 0 then
      self:spawnPartPanel(e, part)
      self:throwDebris(e, part, 3, 55, 165, 1.1, 2.6)
      self.particles:cloudWisp(e.x, e.y,
        (love.math.random() - 0.5) * 34, -10 - love.math.random() * 22,
        6 + love.math.random() * 6, 0.55 + love.math.random() * 0.35,
        { 0.42, 0.44, 0.41 })
      self.particles:cloudWisp(e.x, e.y,
        (love.math.random() - 0.5) * 18, -4 - love.math.random() * 14,
        4 + love.math.random() * 4, 0.35 + love.math.random() * 0.25,
        { 0.78, 0.80, 0.77 })
    end
  elseif band > prev then
    seen[part] = band
  end
end

function NetMatch:spawnKillDebris(e)
  if not e.victim or not self:damageVisible(e.victim) then return end
  self:spawnPartPanel(e, "wing")
  self:spawnPartPanel(e, "tail")
  self:spawnPartPanel(e, "guns")
  self:throwDebris(e, "wing", 4, 70, 190, 1.4, 3.2)
  self:throwDebris(e, "engine", 3, 55, 150, 1.1, 2.6)
  for _ = 1, 3 do
    self.particles:cloudWisp(e.x, e.y,
      (love.math.random() - 0.5) * 60, -20 - love.math.random() * 35,
      6 + love.math.random() * 7, 0.6 + love.math.random() * 0.5,
      { 0.32, 0.34, 0.32 })
  end
end

function NetMatch:processEvents(events)
  for _, e in ipairs(events or {}) do
    if e.type == "shot" then
      if e.owner == self.selfId then
        local best = nil
        local confirmWindow = (self.client.rtt or 0.08) + 0.25
        for _, b in ipairs(self.localBullets) do
          if not b.serverId and (self.uiTime - (b.born or 0)) < confirmWindow then
            if not best or (b.born or 0) < (best.born or 0) then best = b end
          end
        end
        if best then
          best.serverId = e.id
          best.vx = math.cos(e.angle) * C.BULLET.speed
          best.vy = math.sin(e.angle) * C.BULLET.speed
        else
          self.localBullets[#self.localBullets + 1] = {
            x = e.x, y = e.y, px = e.x, py = e.y,
            vx = math.cos(e.angle) * C.BULLET.speed,
            vy = math.sin(e.angle) * C.BULLET.speed,
            life = C.BULLET.life, born = self.uiTime,
            team = self.localTeam or 1, serverId = e.id,
          }
        end
      else
        if self.localPlane and self.localPlane.alive then
          local shooter = self.visuals[e.owner]
          if shooter then
            local dist = M.dist(self.localPlane.x, self.localPlane.y, shooter.x, shooter.y)
            if dist <= C.VISION.revealRange
              and Vision.lineOfSight(self.localPlane, shooter, self.clouds) then
              self.reveal[e.owner] = C.VISION.revealTime
            end
          end
        end
        if not Clouds.pointInside(self.clouds, e.x, e.y) then
          Audio.play("shot", 0.09)
          self.particles:muzzle(e.x, e.y, e.angle, { 1, 0.7, 0.3 })
        end
      end
      if e.owner == self.selfId then self.shake = math.max(self.shake, 0.35) end
    elseif e.type == "hit" then
      Audio.play("hit", e.victim == self.selfId and 0.30 or 0.16)
      self.particles:hit(e.x, e.y, 0, e.victim == self.selfId and { 1, 0.4, 0.3 } or { 1, 0.8, 0.4 })
      if e.owner == self.selfId then
        self.hitMarker = 0.18
        self.hitX, self.hitY = e.x, e.y
        self.shake = math.max(self.shake, 0.9)
        local removed = false
        if e.bulletId then
          for i = #self.localBullets, 1, -1 do
            if self.localBullets[i].serverId == e.bulletId then
              table.remove(self.localBullets, i)
              removed = true
              break
            end
          end
        end
        if not removed then
          local best, bestDist = nil, 90 * 90
          for i, b in ipairs(self.localBullets) do
            local d = (b.x - e.x) ^ 2 + (b.y - e.y) ^ 2
            if d < bestDist then best, bestDist = i, d end
          end
          if best then table.remove(self.localBullets, best) end
        end
      end
      if e.victim == self.selfId then
        self.flash = 0.36
        self.shake = math.max(self.shake, 6)
        self.partFlash[e.part] = 0.30
      end
      self:spawnDamageDebris(e)
      if e.owner == self.selfId or tostring(e.owner) == tostring(self.selfId) then
        self:noteHighlightHit(e)
      end
    elseif e.type == "kill" then
      Audio.play("explosion", e.victim == self.selfId and 0.55 or 0.4)
      local color = e.victim == self.selfId and { 0.45, 0.85, 1 } or { 1, 0.45, 0.25 }
      self.particles:explosion(e.x, e.y, color, e.victim == self.selfId and 1.5 or 1)
      self.particles:fireball(e.x, e.y, e.victim == self.selfId and 1.25 or 1)
      self:spawnKillDebris(e)
      if e.victim == self.selfId then
        self.shake = math.max(self.shake, 9)
        self.flash = 0.55
      elseif e.killer == self.selfId then
        self.notice = "KILL"
        self.noticeTimer = 1.3
      end
    elseif e.type == "pickup" then
      Audio.play("pickup", e.player == self.selfId and 0.24 or 0.08)
      if e.player == self.selfId then
        self.notice = "AMMO +" .. tostring(e.ammo)
        self.noticeTimer = 1.4
      end
      self.particles:flash(e.x, e.y, 5, 0.15, { 1, 0.85, 0.4 })
    elseif e.type == "ram" then
      Audio.play("ram", 0.30)
      Audio.play("explosion", 0.50)
      self.shake = math.max(self.shake, 8)
      self.particles:explosion(e.x, e.y, { 1, 0.55, 0.22 }, 1.15)
      self.particles:flash(e.x, e.y, 8, 0.18, { 1, 0.85, 0.45 })
    elseif e.type == "respawn" then
      Audio.play("respawn", e.id == self.selfId and 0.28 or 0.08)
      if e.id == self.selfId then
        self.notice = "RESPAWNED"
        self.noticeTimer = 1.2
      end
      self.particles:flash(e.x, e.y, 6, 0.2, { 0.55, 0.9, 0.7 })
    elseif e.type == "crash" then
      Audio.play("explosion", 0.6)
      self.particles:explosion(e.x, e.y, { 0.95, 0.58, 0.25 }, e.victim == self.selfId and 1.4 or 1)
      self.particles:fireball(e.x, e.y, 0.85)
      if e.victim == self.selfId then
        self.notice = "CRASHED"
        self.noticeTimer = 1.4
        self.shake = math.max(self.shake, 7)
      end
    elseif e.type == "sides_switched" then
      self.notice = "SIDES SWITCHED"
      self.noticeTimer = 2.5
    elseif e.type == "overheat" then
      Audio.play("overheat", e.player == self.selfId and 0.42 or 0.12)
      if e.player == self.selfId then
        self.notice = "GUNS JAMMED"
        self.noticeTimer = 1.6
      end
    elseif e.type == "round_start" then
      self:setBanner("ROUND " .. tostring(e.round), 1.6)
      self.history = {}
      self.localBullets = {}
      self.localFireTimer = 0
      self.seq = 0
      self.ack = 0
      self.localPlane = nil
      self.localHidden = false
      self.wasStalling = false
      self.reveal = {}
      self.aDown, self.dDown = false, false
      self.lastPitchKey = nil
      self.respawns = {}
      self.leavePrompt = false
      self.promptChoice = 2
    elseif e.type == "round_end" then
      local name = e.winnerTeam and ("TEAM " .. e.winnerTeam)
        or (e.winner and self.names[e.winner] or "NOBODY")
      self:setBanner("ROUND OVER  /  " .. name:upper(), 2.2)
    elseif e.type == "match_end" then
      self.champion = e.champion
      self.mvp = e.mvp
      self.mode = e.mode or self.mode
      self.teamMode = e.teamMode == true
      self.phase = "match_end"
      self.timer = 3
      self.highlight = self.bestReplay
      self.replayClock = 0
    end
  end
end

function NetMatch:recordReplayFrame(msg)
  local frame = { t = self.uiTime, planes = {}, bullets = {}, clouds = {}, focusX = 500, focusY = 220 }
  for _, sp in ipairs(msg.planes or {}) do
    frame.planes[#frame.planes + 1] = {
      id = sp.id, x = sp.x, y = sp.y, a = sp.a, alive = sp.alive,
      team = sp.team, planeType = sp.planeType, hp = sp.hp,
    }
  end
  for _, b in ipairs(msg.bullets or {}) do
    frame.bullets[#frame.bullets + 1] = { x = b.x, y = b.y, vx = b.vx, vy = b.vy, team = b.team }
  end
  for _, c in ipairs(self.clouds.list) do
    frame.clouds[#frame.clouds + 1] = { x = c.x, y = c.y, r = c.r, smoke = c.smoke }
  end
  local p = self.localPlane
  if p then frame.focusX, frame.focusY = p.x, p.y end
  self.replayBuffer[#self.replayBuffer + 1] = frame
  while #self.replayBuffer > 1 and self.uiTime - self.replayBuffer[1].t > 4 do
    table.remove(self.replayBuffer, 1)
  end
end

function NetMatch:noteHighlightHit(e)
  self.replayHits[#self.replayHits + 1] = { t = self.uiTime, damage = e.damage or 0 }
  while #self.replayHits > 1 and self.uiTime - self.replayHits[1].t > 2.5 do
    table.remove(self.replayHits, 1)
  end
  local score = 0
  for _, h in ipairs(self.replayHits) do score = score + h.damage end
  score = score + #self.replayHits * 5
  if score > self.bestReplayScore and #self.replayBuffer >= 1 then
    self.bestReplayScore = score
    self.bestReplay = {}
    for i, frame in ipairs(self.replayBuffer) do self.bestReplay[i] = frame end
  end
end

function NetMatch:drawHighlight(x, y, w, h)
  love.graphics.push("all")
  love.graphics.setScissor(x, y, w, h)
  love.graphics.setColor(0.012, 0.02, 0.025, 1)
  love.graphics.rectangle("fill", x, y, w, h)
  local frames = self.highlight
  if not frames or #frames == 0 then
    UI.set(UI.C.cream2)
    UI.small("NO HIGHLIGHT", x, y + h * 0.5 - 4, UI.C.cream2, "center", w)
    love.graphics.setScissor()
    love.graphics.pop()
    return
  end
  local progress = math.min(0.999, (self.replayClock or 0) / 2.6)
  local frame = frames[math.max(1, math.floor(progress * #frames) + 1)]
  local sx, sy = w / 300, h / 170
  local s = math.min(sx, sy)
  local fx, fy = frame.focusX or 500, frame.focusY or 220
  love.graphics.setColor(0.43, 0.62, 0.72, 1)
  love.graphics.rectangle("fill", x, y, w, h)
  love.graphics.push()
  love.graphics.translate(x + w * 0.5, y + h * 0.5)
  love.graphics.scale(s, s)
  love.graphics.translate(-fx, -fy)
  love.graphics.setColor(0.20, 0.24, 0.19, 1)
  love.graphics.rectangle("fill", -400, C.WORLD.groundY, 1800, 120)
  for _, c in ipairs(frame.clouds or {}) do
    love.graphics.setColor(c.smoke and 0.24 or 0.86, c.smoke and 0.22 or 0.88,
      c.smoke and 0.20 or 0.86, 0.32)
    love.graphics.circle("fill", c.x, c.y, c.r or 36, 12)
  end
  for _, b in ipairs(frame.bullets or {}) do
    love.graphics.setColor(1, 0.82, 0.35, 0.9)
    love.graphics.line(b.x, b.y, b.x - (b.vx or 0) * 0.035, b.y - (b.vy or 0) * 0.035)
  end
  for _, p in ipairs(frame.planes or {}) do
    if p.alive then
      local spec = Aircraft.get(p.planeType)
      local plane = { x = p.x, y = p.y, angle = p.a, team = p.team,
        planeType = p.planeType, spec = spec, parts = { engine = 60, wing = 60, tail = 60, guns = 60 } }
      local colors = (p.team == 1) and Sprites.TEAM.player or Sprites.TEAM.enemy
      Sprites.drawPlane(plane, self.uiTime, { colors = colors })
    end
  end
  love.graphics.pop()
  love.graphics.setScissor()
  UI.set(UI.C.orange)
  love.graphics.setFont(UI.font(7, true))
  love.graphics.print("BEST STRIKE", x + 4, y + 4)
  love.graphics.pop()
end

function NetMatch:syncClouds(data)
  if not data then return end
  local existing = {}
  for _, c in ipairs(self.clouds.list) do existing[c.id] = c end
  local list = {}
  for _, d in ipairs(data) do
    local c = existing[d.id]
    if c then
      if math.abs(d.x - c.x) > 1.5 then c.x = d.x end
      if math.abs(d.y - c.y) > 1.5 then c.y = d.y end
      c.r, c.variant = d.r or c.r, d.variant or c.variant
      c.alpha, c.speed = d.alpha or c.alpha, d.speed or c.speed
      c.smoke = d.smoke == true
      c.life, c.maxLife = d.life, d.maxLife
      if c.smoke then c.tint = { 0.30, 0.27, 0.24 } end
    else
      c = {
        id = d.id, x = d.x, y = d.y, r = d.r or 40,
        variant = d.variant or 1, alpha = d.alpha or 0.88,
        speed = d.speed or 0, smoke = d.smoke == true,
        life = d.life, maxLife = d.maxLife,
        baseAlpha = d.alpha or 0.88,
        tint = d.smoke and { 0.30, 0.27, 0.24 } or nil,
        puffs = Shapes.puffs(d.variant or 1, d.r or 40),
      }
    end
    list[#list + 1] = c
  end
  self.clouds.list = list
end

function NetMatch:clearSmokeClouds()
  if not self.clouds then return end
  for i = #self.clouds.list, 1, -1 do
    if self.clouds.list[i].smoke then table.remove(self.clouds.list, i) end
  end
end

function NetMatch:onSnapshot(msg)
  self.snapshot = msg
  self.snapRecvAt = love.timer.getTime()
  if msg.phase == "prep" and self.phase ~= "prep" then
    self:clearSmokeClouds()
  end
  self.phase = msg.phase
  self.round = msg.round
  self.timer = msg.timer
  self.champion = msg.champion
  self.mvp = msg.mvp
  self.roundWinner = msg.roundWinner
  self.mode = msg.mode or self.mode
  self.rounds = msg.rounds or self.rounds
  self.teamMode = msg.teamMode == true
  self.teamKills = msg.teamKills or { [1] = 0, [2] = 0 }
  self.teamWins = msg.teamWins or { [1] = 0, [2] = 0 }

  self.scores = {}
  for _, s in ipairs(msg.scores or {}) do
    self.scores[s.id] = {
      wins = s.wins, kills = s.kills, roundKills = s.roundKills or 0,
      team = s.team,
    }
  end

  self.respawns = {}
  for _, r in ipairs(msg.respawns or {}) do
    self.respawns[r.id] = r.t
  end

  -- Cloud positions are server-authoritative: a client joining late, lagging,
  -- or drifting between frames must not use a different cloud field for
  -- visibility, otherwise it can stay invisible after leaving a cloud.
  self:syncClouds(msg.clouds)

  local own = nil
  local seen = {}
  for _, sp in ipairs(msg.planes or {}) do
    seen[sp.id] = true
    if sp.id == self.selfId then own = sp end

    local v = self.visuals[sp.id]
    if not v then
      v = {
        x = sp.x, y = sp.y, angle = sp.a, hp = sp.hp,
        maxHp = sp.maxHp or sp.hp, planeType = sp.planeType or "ik3",
        spec = Aircraft.get(sp.planeType),
        alive = sp.alive, hidden = sp.hidden == true, parts = sp.parts, ammo = sp.ammo,
        seenBy = sp.seenBy, team = sp.team,
      }
      self.visuals[sp.id] = v
    end
    self.visualTargets = self.visualTargets or {}
    self.visualTargets[sp.id] = sp
  end

  for id in pairs(self.visuals) do
    if not seen[id] then
      self.visuals[id] = nil
      if self.visualTargets then self.visualTargets[id] = nil end
    end
  end

  if self.spectator or not own then
    self.localPlane = nil
    self.localHidden = false
  else
    self.localHidden = own.hidden == true
    if not self.localPlane then
      self.localPlane = Flight.new({
        id = self.selfId, x = own.x, y = own.y, angle = own.a, speed = 200,
        team = own.team or self.selfId, name = self.names[self.selfId] or "Pilot",
        planeType = own.planeType,
      })
    end
    copyServerPlane(self.localPlane, own)
    self.localTeam = own.team or self.selfId
    self.ack = own.ack or 0

    local keep = {}
    for _, h in ipairs(self.history) do
      if h.seq > self.ack then
        Flight.step(self.localPlane, h.input, C.TICK)
        keep[#keep + 1] = h
      end
    end
    self.history = keep
  end

  self:processEvents(msg.events)
  self:recordReplayFrame(msg)
end

function NetMatch:updateVisuals(dt)
  for id, target in pairs(self.visualTargets or {}) do
    local v = self.visuals[id]
    if v then
      v.prevX, v.prevY, v.prevAngle = v.x, v.y, v.angle
      local k = 1 - math.exp(-15 * dt)
      v.x = v.x + (target.x - v.x) * k
      v.y = v.y + (target.y - v.y) * k
      if dt > 0.0001 then
        v.vx = (v.x - v.prevX) / dt
        v.vy = (v.y - v.prevY) / dt
      end
      v.angle = v.angle + M.angleDiff(v.angle, target.a) * k
      v.hp = target.hp
      v.alive = target.alive
      v.hidden = target.hidden == true
      v.seenBy = target.seenBy
      v.team = target.team
      v.parts = target.parts
      v.ammo = target.ammo
    end
  end
  if self.localPlane then
    local v = self.visuals[self.selfId]
    if v then
      v.x, v.y, v.angle = self.localPlane.x, self.localPlane.y, self.localPlane.angle
      v.hp, v.alive, v.parts, v.ammo =
        self.localPlane.hp, self.localPlane.alive, self.localPlane.parts, self.localPlane.ammo
    end
  end
end

function NetMatch:updateCamera(dt)
  local target = nil
  if self.localPlane and self.localPlane.alive and not self.spectator then
    target = self.localPlane
  else
    local list = {}
    for id, v in pairs(self.visuals) do
      if v.alive and id ~= self.selfId then
        list[#list + 1] = { id = id, x = v.x, y = v.y }
      end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    local chosen = nil
    for _, item in ipairs(list) do
      if item.id == self.spectateId then chosen = item; break end
    end
    if not chosen and #list > 0 then
      chosen = list[1]
      local best = -1
      for _, item in ipairs(list) do
        local score = self.scores[item.id]
        local value = score and (score.wins * 100 + score.kills) or -1
        if value > best then best, chosen = value, item end
      end
    end
    if chosen then
      self.spectateId = chosen.id
      target = chosen
    end
  end
  if target then Camera.follow(self.camera, target.x, target.y, dt) end
end

function NetMatch:cycleSpectator(dir)
  local ids = {}
  for id, v in pairs(self.visuals) do
    if v.alive and id ~= self.selfId then ids[#ids + 1] = id end
  end
  table.sort(ids)
  if #ids == 0 then return end
  local current = 1
  for i, id in ipairs(ids) do if id == self.spectateId then current = i; break end end
  current = ((current - 1 + dir) % #ids) + 1
  self.spectateId = ids[current]
end

function NetMatch:update(dt)
  if self.exited then return end

  self.client:update(dt)
  for _, msg in ipairs(self.client:takeMessages()) do
    self:handleMessage(msg)
    if self.exited then return end
  end
  if self.client.status == "closed" or self.client.status == "error" then
    self.client.matchActive = false
    self.client.notice = self.client.errorMessage or "DISCONNECTED"
    self.exited = true
    App:pop()
    return
  end

  self.uiTime = self.uiTime + dt
  self.chatTimer = math.max(0, (self.chatTimer or 0) - dt)
  self.replayClock = (self.replayClock or 0) + dt
  self.bannerTimer = math.max(0, self.bannerTimer - dt)
  self.noticeTimer = math.max(0, self.noticeTimer - dt)
  self.hintTimer = math.max(0, self.hintTimer - dt)
  self.flash = math.max(0, self.flash - dt * 2.2)
  self.shake = math.max(0, self.shake - dt * 18)
  self.hitMarker = math.max(0, self.hitMarker - dt)
  for k, v in pairs(self.partFlash) do self.partFlash[k] = math.max(0, v - dt) end
  for id, t in pairs(self.reveal) do
    t = t - dt
    if t <= 0 then self.reveal[id] = nil else self.reveal[id] = t end
  end
  if self.localPlane then
    self.hullGhost = damp(self.hullGhost, self.localPlane.hp / self.localPlane.maxHp, 4, dt)
    if self.localPlane.alive and self.localPlane.stalling and not self.wasStalling then
      Audio.play("stall", 0.22)
    end
    self.wasStalling = self.localPlane.stalling
  end

  if self.phase == "round" then
    Clouds.update(self.clouds, dt)
    Clouds.update(self.farClouds, dt)
  end
  self.particles:update(dt)
  self:updateVisuals(dt)
  self.cloudFx:update(dt, self.localPlane, self.clouds, self.particles, true)
  self.dustTimer = self.dustTimer or {}
  for id, v in pairs(self.visuals) do
    if v.alive and v.y > C.WORLD.groundY - 58 then
      self.dustTimer[id] = (self.dustTimer[id] or 0) - dt
      if self.dustTimer[id] <= 0 then
        self.dustTimer[id] = 0.09
        self.particles:cloudWisp(v.x, C.WORLD.groundY - 2,
          (love.math.random() - 0.5) * 30, -8 - love.math.random() * 16,
          3 + love.math.random() * 4, 0.4 + love.math.random() * 0.25,
          { 0.50, 0.44, 0.31 })
      end
    end
  end
  self:updateCamera(dt)
  if self.localPlane and self.localPlane.alive and not self.spectator then
    local seen = {}
    for id, v in pairs(self.visuals) do
      if id ~= self.selfId and v.alive then
        seen[id] = true
        Audio.setEngine(id,
          v.x - self.localPlane.x, v.y - self.localPlane.y,
          (self.visualTargets[id] and self.visualTargets[id].throttle) or 0.6,
          true, Clouds.pointInside(self.clouds, v.x, v.y), v.vx or 0, v.vy or 0)
      end
    end
    for id in pairs(Audio.engines) do
      if not seen[id] then Audio.setEngine(id, 0, 0, 0, false) end
    end
  else
    Audio.stopEngines()
  end

  -- Remote damage smoke only. Engine exhaust trails were removed because they
  -- could smear from the snapshot position while the predicted plane was
  -- elsewhere, looking like thrust from a second direction.
  for id, target in pairs(self.visualTargets or {}) do
    if id ~= self.selfId then
      if target.alive and target.parts and target.parts.engine < 30 and love.math.random() < 0.15 then
        self.particles:smoke(target.x, target.y,
          (love.math.random() - 0.5) * 14, -20, 3, 0.7, { 0.17, 0.17, 0.17 })
      end
    end
  end

  if self.localPlane and self.localPlane.alive then
    self.dmgSmokeTimer = (self.dmgSmokeTimer or 0) - dt
    local p = self.localPlane
    local worst = math.min(p.parts.engine or 60, p.parts.wing or 60, p.parts.tail or 60)
    if worst < 35 and self.dmgSmokeTimer <= 0 then
      self.dmgSmokeTimer = 0.09 + worst / 400
      local dir = math.atan2(p.vy, p.vx)
      local bx, by = -math.cos(dir), -math.sin(dir)
      self.particles:cloudWisp(
        p.x + bx * (8 + love.math.random() * 10) + (love.math.random() - 0.5) * 8,
        p.y + by * (8 + love.math.random() * 10) + (love.math.random() - 0.5) * 8,
        bx * 14 + (love.math.random() - 0.5) * 18,
        by * 14 - 8 + (love.math.random() - 0.5) * 18,
        3 + love.math.random() * 5, 0.45 + love.math.random() * 0.35,
        { 0.30 + worst / 300, 0.31 + worst / 320, 0.30 + worst / 340 })
    end
  end

  local mx, my = View.mouse()
  self.hover = nil
  if self.leavePrompt then
    if UI.hit(mx, my, 214, 188, 100, 26) then self.hover = "leave" end
    if UI.hit(mx, my, 326, 188, 100, 26) then self.hover = "stay" end
  elseif self.spectator and self.phase == "prep" and self.joinQueued == false then
    if UI.hit(mx, my, 244, 300, 152, 24) then self.hover = "join" end
  end
end

function NetMatch:inputForTick()
  local p = self.localPlane
  if not p or not p.alive or self.spectator then return nil end

  local up = Controls.isDown("throttleUp")
  local down = Controls.isDown("throttleDown")
  if up and not down then
    self.input.throttle = math.min(1, self.input.throttle + 1.2 * C.TICK)
  elseif down and not up then
    self.input.throttle = math.max(0, self.input.throttle - 1.2 * C.TICK)
  end

  -- A/D are plane-relative: A always rotates counter-clockwise, D clockwise.
  -- The newest pressed direction stays active until it is released.
  local a = Controls.isDown("pitchLeft")
  local d = Controls.isDown("pitchRight")
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
  self.input.fire = Controls.isDown("fire")
    or (_G.DOGFIGHT and _G.DOGFIGHT.opts and _G.DOGFIGHT.opts.autofire == true)
  return self.input
end

function NetMatch:updateLocalBullets(dt, input)
  local p = self.localPlane
  if not p then return end

  self.localFireTimer = math.max(0, self.localFireTimer - dt)
  if input and input.fire and p.alive and not self.spectator
    and (p.parts.guns or 0) > 0 and (p.ammo or 0) > 0
    and (p.jammed or 0) <= 0 and (p.heat or 0) < 1 and self.localFireTimer <= 0 then
    self.localFireTimer = Flight.fireInterval(p)
    local x, y = Combat.toWorld(p, 18, 0)
    self.localBullets[#self.localBullets + 1] = {
      x = x, y = y, px = x, py = y,
      vx = math.cos(p.angle) * C.BULLET.speed,
      vy = math.sin(p.angle) * C.BULLET.speed,
      life = C.BULLET.life, born = self.uiTime, team = self.localTeam or 1,
      serverId = nil,
    }
    self.particles:muzzle(x, y, p.angle, { 0.55, 0.95, 0.95 })
    p.heat = math.min(1, (p.heat or 0) + C.GUN.heatPerShot)
    if p.heat >= 1 then p.jammed = C.GUN.jamTime end
    Audio.play("shot", 0.18)
    self.shake = math.max(self.shake, 0.35)
  end

  local i = 1
  while i <= #self.localBullets do
    local b = self.localBullets[i]
    b.px, b.py = b.x, b.y
    b.x = b.x + b.vx * dt
    b.y = b.y + b.vy * dt
    b.life = b.life - dt
    local stale = not b.serverId
      and (self.uiTime - (b.born or 0)) > ((self.client.rtt or 0.08) + 0.25)
    if not stale and b.life > 0 and b.x >= C.WORLD.wallLeft and b.x <= C.WORLD.wallRight
      and b.y >= -10 and b.y <= C.WORLD.groundY then
      for id, v in pairs(self.visuals) do
        if id ~= self.selfId and v.alive
          and not (self.teamMode and v.team == self.localTeam) then
          local b2 = { owner = self.selfId, px = b.px, py = b.py, x = b.x, y = b.y,
            radius = C.BULLET.radius }
          local part = Combat.bulletHitsMovingPlane(b2, v,
            v.prevX or v.x, v.prevY or v.y, v.prevAngle or v.angle,
            C.WORLD.w, C.WORLD.h)
          if part then
            -- Predicted impact is visual only. The server still decides damage.
            b.life = 0
            break
          end
        end
      end
    end
    if b.life <= 0 or stale or b.x < C.WORLD.wallLeft or b.x > C.WORLD.wallRight
      or b.y < -10 or b.y > C.WORLD.groundY then
      self.localBullets[i] = self.localBullets[#self.localBullets]
      self.localBullets[#self.localBullets] = nil
    else
      i = i + 1
    end
  end
end

function NetMatch:fixedUpdate(dt)
  if self.exited or self.leavePrompt then return end
  if not self.spectator and self.phase == "round" then
    local input = self:inputForTick()
    if input then
      self.seq = self.seq + 1
      local packaged = {
        seq = self.seq,
        throttle = self.input.throttle,
        pitch = self.input.pitch,
        fire = self.input.fire,
      }
      self.history[#self.history + 1] = { seq = self.seq, input = packaged }
      if #self.history > 150 then table.remove(self.history, 1) end
      Flight.step(self.localPlane, packaged, dt)
      packaged.aim = self.localPlane.angle
      self:updateLocalBullets(dt, packaged)
      self.client:send({
        type = "input", seq = packaged.seq, throttle = packaged.throttle,
        pitch = packaged.pitch, fire = packaged.fire, aim = packaged.aim,
        rtt = math.floor((self.client.rtt or 0.08) * 1000),
      })
    end
  end
end

-------------------------------------------------------------------------------
-- rendering
-------------------------------------------------------------------------------

function NetMatch:drawWorld()
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
  CloudShadows.draw(self.clouds)

  local snap = self.snapshot
  local age = math.min(0.15, love.timer.getTime() - self.snapRecvAt)
  if snap then
    for _, b in ipairs(snap.bullets or {}) do
      if b.owner ~= self.selfId then
        local bullet = {
          x = b.x + b.vx * age, y = b.y + b.vy * age,
          vx = b.vx, vy = b.vy, owner = b.owner,
          team = b.team or 2,
        }
        if bullet.x > -10 and bullet.x < W + 10 and bullet.y > -10 and bullet.y < H + 10
          and not Clouds.pointInside(self.clouds, bullet.x, bullet.y) then
          Sprites.drawBullet(bullet)
        end
      end
    end

    -- Own tracer: predicted immediately, then reconciled by shot ID to the
    -- authoritative bullet. It is removed on the server's confirmed hit.
    for _, b in ipairs(self.localBullets) do
      if b.x > C.WORLD.wallLeft and b.x < C.WORLD.wallRight
        and b.y > -10 and b.y < C.WORLD.groundY
        and not Clouds.pointInside(self.clouds, b.x, b.y) then
        Sprites.drawBullet({ x = b.x, y = b.y, vx = b.vx, vy = b.vy,
          team = b.team or self.localTeam or 1 })
      end
    end
    for _, p in ipairs(snap.pickups or {}) do
      local pickup = { x = p.x, y = p.y + p.vy * age, phase = 0 }
      Sprites.drawPickup(pickup, self.uiTime)
    end
  end

  self.particles:draw()

  -- Remote planes.
  for id, v in pairs(self.visuals) do
    if id ~= self.selfId and v.alive then
      local visible = true
      if not self.spectator and self.localPlane and self.localPlane.alive then
        if v.seenBy then
          visible = false
          for _, viewerId in ipairs(v.seenBy) do
            if viewerId == self.selfId then visible = true; break end
          end
        else
          visible = Vision.canSee(self.localPlane, v, self.clouds)
        end
      end
      local reveal = (not visible) and (self.reveal[id] or 0) > 0
      if visible or reveal then
        local plane = {
          x = v.x, y = v.y, angle = v.angle, throttle = 0.6, alive = true,
          invuln = 0, hitFlash = 0, parts = v.parts or {},
          team = v.team or 2,
        }
        local friendly = self.teamMode and v.team == self.localTeam
        local colors
        if self.teamMode then
          colors = (v.team == 1) and Sprites.TEAM.player or Sprites.TEAM.enemy
        elseif friendly then
          colors = Sprites.TEAM.player
        else
          colors = Sprites.TEAM.enemy
        end
        Sprites.drawPlaneCopies(plane, self.uiTime, {
          colors = colors,
          alpha = reveal and 0.25 or 1,
        })
        if visible then
          love.graphics.setFont(UI.font(7))
          UI.set(friendly and UI.C.teal or UI.C.cream)
          local labelX = M.clamp(v.x - 30, C.WORLD.wallLeft, C.WORLD.wallRight - 60)
          local barX = M.clamp(v.x - 15, C.WORLD.wallLeft + 2, C.WORLD.wallRight - 32)
          love.graphics.printf(self.names[id] or ("PILOT" .. id), labelX, v.y - 28, 60, "center")
          love.graphics.setColor(0.08, 0.10, 0.09, 0.8)
          love.graphics.rectangle("fill", barX, v.y - 19, 30, 3)
          love.graphics.setColor(0.85, 0.40, 0.25, 0.95)
          love.graphics.rectangle("fill", barX, v.y - 19, 30 * (v.hp / (v.maxHp or C.PLANE.hp)), 3)
        end
      end
    end
  end

  local playerHidden = false
  if self.localPlane and self.localPlane.alive then
    playerHidden = self.localHidden
    local localColors = (self.teamMode and self.localTeam == 2)
      and Sprites.TEAM.enemy or Sprites.TEAM.player
    Sprites.drawPlaneCopies(self.localPlane, self.uiTime, { colors = localColors })
  end

  if dd.enabled then
    dd.grid(0, 0, W, H, 40, { 0.4, 0.5, 0.6, 0.10 })
    for _, p in ipairs({ self.localPlane }) do
      if p and p.alive then
        for _, s in ipairs(Combat.SHAPES) do
          local x, y = Combat.toWorld(p, s.x, s.y)
          dd.circle(x, y, s.r, s.part == "wing" and UI.C.orange or UI.C.teal, 12)
        end
      end
    end
    for _, cloud in ipairs(self.clouds.list) do
      for _, puff in ipairs(cloud.puffs) do
        dd.circle(cloud.x + puff.dx, cloud.y + puff.dy, puff.r, UI.C.cream2, 16)
      end
    end
  end

  if self.hitMarker > 0 then
    local a = math.min(1, self.hitMarker / 0.18)
    love.graphics.setColor(1, 0.94, 0.72, a)
    love.graphics.line(self.hitX - 4, self.hitY - 4, self.hitX + 4, self.hitY + 4)
    love.graphics.line(self.hitX + 4, self.hitY - 4, self.hitX - 4, self.hitY + 4)
  end

  love.graphics.pop()

  for _, cloud in ipairs(self.clouds.list) do
    Sprites.drawCloudCopies(cloud, 1)
  end
  self.cloudFx:drawWake()
  self.particles:drawFire()
  self.particles:drawCloud()
  self.particles:drawDebris()
  self.particles:drawPanels()

  if playerHidden and self.localPlane then
    local ghostColors = (self.teamMode and self.localTeam == 2)
      and Sprites.TEAM.enemy or Sprites.TEAM.player
    Sprites.drawPlaneCopies(self.localPlane, self.uiTime, { colors = ghostColors, alpha = 0.55 })
  end

  love.graphics.pop()
end

function NetMatch:drawHud()
  local p = self.localPlane
  local sw = 640

  -- round / timer
  UI.set(UI.C.ink, 0.62)
  love.graphics.rectangle("fill", 236, 8, 168, 24)
  UI.set(UI.C.cream2)
  love.graphics.rectangle("line", 236.5, 8.5, 167, 23)
  love.graphics.setFont(UI.font(9, true))
  UI.set(UI.C.cream)
  if self.mode == "demo" then
    love.graphics.printf("DEMO", 236, 14, 168, "center")
  else
    love.graphics.printf(string.format("ROUND %d / %d", self.round or 1, self.rounds or C.ROUNDS), 236, 14, 168, "center")
  end
  UI.set(UI.C.orange)
  local aliveAll, aliveTeams = 0, { [1] = 0, [2] = 0 }
  for id, v in pairs(self.visuals) do
    if v.alive then
      aliveAll = aliveAll + 1
      if self.teamMode and (v.team == 1 or v.team == 2) then
        aliveTeams[v.team] = aliveTeams[v.team] + 1
      end
    end
  end
  local target
  if self.teamMode then
    target = string.format("T1 %d   T2 %d", aliveTeams[1] or 0, aliveTeams[2] or 0)
  else
    target = "ALIVE " .. tostring(aliveAll)
  end
  if self.teamMode then
    UI.set(UI.C.ink, 0.62)
    love.graphics.rectangle("fill", 236, 34, 168, 16)
    UI.set(UI.C.orange)
    love.graphics.setFont(UI.font(7, true))
    love.graphics.printf(target, 236, 38, 168, "center")
  else
    love.graphics.printf(target, 300, 14, 104, "right")
  end

  local rttMs = math.floor((self.client.rtt or 0) * 1000 + 0.5)
  if rttMs > 0 then
    UI.set(rttMs < 80 and UI.C.green or (rttMs < 160 and UI.C.orange or UI.C.red))
    love.graphics.setFont(UI.font(7, true))
    love.graphics.print(string.format("PING %dMS", rttMs), 190, 10)
  end

  -- local hull
  if p and not self.spectator then
    UI.panel(8, 8, 176, 54, { color = { 0.04, 0.06, 0.05, 0.72 }, border = UI.C.ink3 })
    love.graphics.setFont(UI.font(7))
    UI.set(UI.C.cream2)
    love.graphics.print("HULL", 16, 14)
    local frac = p.hp / p.maxHp
    love.graphics.setColor(0.10, 0.12, 0.10, 0.9)
    love.graphics.rectangle("fill", 16, 26, 160, 7)
    if self.hullGhost > frac then
      love.graphics.setColor(1, 0.52, 0.24, 0.85)
      love.graphics.rectangle("fill", 16 + 160 * frac, 26, 160 * (self.hullGhost - frac), 7)
    end
    local hpColor = frac > 0.5 and UI.C.green or (frac > 0.25 and UI.C.orange or UI.C.red)
    love.graphics.setColor(hpColor[1], hpColor[2], hpColor[3], 1)
    love.graphics.rectangle("fill", 16, 26, 160 * frac, 7)
    UI.set(UI.C.cream)
    love.graphics.setFont(UI.font(9, true))
    love.graphics.printf(tostring(math.ceil(p.hp)), 16, 25, 160, "right")

    local parts = {
      { "ENG", p.parts.engine, "engine" }, { "WING", p.parts.wing, "wing" },
      { "TAIL", p.parts.tail, "tail" }, { "GUN", p.parts.guns, "guns" },
    }
    for i, part in ipairs(parts) do
      local x = 16 + (i - 1) * 40
      local pf = part[2] / ((p.spec and p.spec.stats.partHp) or C.PLANE.partHp)
      love.graphics.setFont(UI.font(6))
      UI.set(UI.C.cream2)
      love.graphics.print(part[1], x, 40)
      love.graphics.setColor(0.10, 0.12, 0.10, 0.9)
      love.graphics.rectangle("fill", x, 49, 34, 3)
      local col = pf > 0.5 and UI.C.green or (pf > 0.2 and UI.C.orange or UI.C.red)
      love.graphics.setColor(col[1], col[2], col[3], 1)
      love.graphics.rectangle("fill", x, 49, 34 * pf, 3)
      if (self.partFlash[part[3]] or 0) > 0 then
        love.graphics.setColor(1, 1, 1, 0.55)
        love.graphics.rectangle("fill", x, 49, 34, 3)
      end
    end

    UI.panel(8, 312, 160, 40, { color = { 0.04, 0.06, 0.05, 0.72 }, border = UI.C.ink3 })
    love.graphics.setFont(UI.font(7))
    UI.set(UI.C.cream2)
    love.graphics.print(string.format("THR %d%%", math.floor(p.throttle * 100)), 16, 318)
    love.graphics.setColor(0.1, 0.12, 0.1, 0.9)
    love.graphics.rectangle("fill", 16, 330, 70, 6)
    love.graphics.setColor(UI.C.teal[1], UI.C.teal[2], UI.C.teal[3], 1)
    love.graphics.rectangle("fill", 16, 330, 70 * p.throttle, 6)
    love.graphics.setFont(UI.font(8, true))
    UI.set(UI.C.cream)
    love.graphics.printf(string.format("%03d", math.floor(math.sqrt(p.vx * p.vx + p.vy * p.vy))),
      90, 318, 70, "right")

    UI.panel(512, 312, 120, 40, { color = { 0.04, 0.06, 0.05, 0.72 }, border = UI.C.ink3 })
    love.graphics.setFont(UI.font(7))
    UI.set(UI.C.cream2)
    love.graphics.print("AMMO", 520, 318)
    love.graphics.setFont(UI.font(12, true))
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
  end

  -- scoreboard
  local rows = {}
  for id, s in pairs(self.scores or {}) do
    rows[#rows + 1] = {
      id = id, wins = s.wins, kills = s.kills,
      roundKills = s.roundKills or 0, team = s.team,
      name = self.names[id] or ("P" .. id),
    }
  end
  table.sort(rows, function(a, b)
    if a.wins ~= b.wins then return a.wins > b.wins end
    if a.kills ~= b.kills then return a.kills > b.kills end
    return a.id < b.id
  end)
  love.graphics.setFont(UI.font(7))
  local scoreW = 96
  for _, r in ipairs(rows) do
    local text = string.format("%s%s  %dW/%dK  R%d",
      self.teamMode and ("T" .. tostring(r.team or "?") .. " ") or "",
      r.name, r.wins, r.kills, r.roundKills or 0)
    scoreW = math.max(scoreW, UI.font(7):getWidth(text) + 16)
  end
  scoreW = math.min(230, scoreW)
  local scoreX = 636 - scoreW
  UI.set(UI.C.ink, 0.92)
  love.graphics.rectangle("fill", scoreX, 60, scoreW, 52)
  UI.set(UI.C.ink3)
  love.graphics.rectangle("line", scoreX + 0.5, 60.5, scoreW - 1, 51)
  for i = 1, math.min(4, #rows) do
    local r = rows[i]
    if r.id == self.selfId then
      UI.set(UI.C.orange)
    elseif self.teamMode then
      UI.set((r.team == 1) and UI.C.teal or UI.C.cream2)
    else
      UI.set(UI.C.cream2)
    end
    love.graphics.printf(string.format("%s%s  %dW/%dK  R%d",
      self.teamMode and ("T" .. tostring(r.team or "?") .. " ") or "",
      r.name, r.wins, r.kills, r.roundKills or 0),
      scoreX + 7, 64 + (i - 1) * 11, scoreW - 13, "right")
  end

  -- spectator / death
  if self.spectator then
    UI.set(UI.C.ink, 0.7)
    love.graphics.rectangle("fill", 8, 64, 120, 20)
    UI.set(UI.C.orange)
    love.graphics.setFont(UI.font(8, true))
    love.graphics.printf("SPECTATING", 8, 69, 120, "center")
  elseif p and not p.alive then
    local respawnIn = self.respawns and self.respawns[self.selfId]
    love.graphics.setFont(UI.font(14, true))
    UI.set(UI.C.red)
    if respawnIn then
      love.graphics.printf(string.format("RESPAWN IN %.1f", math.max(0, respawnIn)), 0, 142, 640, "center")
    else
      love.graphics.printf("SPECTATING  /  NEXT ROUND", 0, 142, 640, "center")
    end
  end

  if (self.spectator or (p and not p.alive)) and self.spectateId then
    UI.set(UI.C.ink, 0.55)
    love.graphics.rectangle("fill", 170, 160, 300, 14)
    UI.set(UI.C.cream)
    love.graphics.setFont(UI.font(7))
    love.graphics.printf("FOLLOWING " .. (self.names[self.spectateId] or ("P" .. self.spectateId))
      .. "   /   [ ] SWITCH", 170, 164, 300, "center")
  end

  if p and p.alive and not self.spectator and p.stalling then
    if math.floor(self.uiTime * 6) % 2 == 0 then
      UI.set(UI.C.red)
      love.graphics.setFont(UI.font(14, true))
      love.graphics.printf("STALL", 0, 154, 640, "center")
    end
  end

  if self.localPlane and not self.spectator and self.localHidden then
    UI.set(UI.C.teal)
    love.graphics.setFont(UI.font(8, true))
    love.graphics.printf("CLOUD COVER", 0, 168, 640, "center")
  end

  if self.hintTimer > 0 and self.localPlane and not self.spectator
    and not self.leavePrompt and self.phase == "round" then
    local alpha = math.min(1, self.hintTimer / 2)
    love.graphics.setColor(0.02, 0.04, 0.04, 0.6 * alpha)
    love.graphics.rectangle("fill", 170, 288, 300, 16)
    UI.set(UI.C.cream2, alpha)
    love.graphics.setFont(UI.font(7))
    love.graphics.printf(string.format("%s/%s THROTTLE  /  %s/%s PITCH  /  %s FIRE  /  ESC MENU",
      Controls.label("throttleUp"), Controls.label("throttleDown"),
      Controls.label("pitchLeft"), Controls.label("pitchRight"),
      Controls.label("fire")), 170, 293, 300, "center")
  end

  if self.noticeTimer > 0 and self.notice then
    UI.set(UI.C.cream)
    love.graphics.setFont(UI.font(9, true))
    love.graphics.printf(self.notice, 0, 184, 640, "center")
  end

  if self.bannerTimer > 0 and self.banner then
    local alpha = math.min(1, self.bannerTimer * 2)
    love.graphics.setColor(0.02, 0.04, 0.04, 0.6 * alpha)
    love.graphics.rectangle("fill", 0, 196, 640, 34)
    UI.set(self.champion and UI.C.orange or UI.C.cream, alpha)
    love.graphics.setFont(UI.font(14, true))
    love.graphics.printf(self.banner, 0, 204, 640, "center")
  end

  if self.phase == "prep" then
    UI.set(UI.C.ink, 0.72)
    love.graphics.rectangle("fill", 160, 236, 320, 46)
    UI.set(UI.C.orange)
    love.graphics.rectangle("line", 160.5, 236.5, 319, 45)
    love.graphics.setFont(UI.font(12, true))
    UI.set(UI.C.orange)
    love.graphics.printf(self.mode == "demo" and "DEMO STARTS IN" or ("ROUND " .. tostring(self.round or 1)),
      160, 244, 320, "center")
    love.graphics.setFont(UI.font(9))
    UI.set(UI.C.cream)
    love.graphics.printf(string.format("STARTS IN %.0f", math.max(0, math.ceil(self.timer or 0))),
      160, 262, 320, "center")
  end

  if self.flash > 0 then
    love.graphics.setColor(0.85, 0.12, 0.10, self.flash * 0.35)
    love.graphics.rectangle("fill", 0, 0, 640, 360)
  end

  if Settings.data.showFps then
    UI.set(UI.C.cream2)
    love.graphics.setFont(UI.font(7))
    love.graphics.print(string.format("%d FPS", Debug.fps), 304, 30)
  end

  if self.phase == "match_end" then
    local name, color = "NOBODY", UI.C.cream
    if self.champion then
      if (self.teamMode or self.mode == "1v1") and (self.champion == 1 or self.champion == 2) then
        name = (self.champion == 1) and "BLUE" or "RED"
        color = (self.champion == 1) and UI.C.teal or UI.C.orange
      else
        name = self.names[self.champion] or ("P" .. tostring(self.champion))
      end
    end
    love.graphics.setColor(0.02, 0.03, 0.035, 0.72)
    love.graphics.rectangle("fill", 0, 0, 640, 360)
    UI.set(color)
    love.graphics.setFont(UI.font(20, true))
    local label = name:upper() .. " WON THE WAR"
    love.graphics.printf(label, 0, 142, 640, "center")
    UI.set(UI.C.cream2)
    love.graphics.setFont(UI.font(8))
    local mvpName = self.mvp and (self.names[self.mvp] or ("P" .. tostring(self.mvp))) or "NOBODY"
    love.graphics.printf("MVP: " .. mvpName:upper(), 0, 168, 640, "center")
    love.graphics.printf("RETURNING TO LOBBY", 0, 190, 640, "center")
    self:drawHighlight(400, 54, 210, 118)
  end
end

function NetMatch:drawLeavePrompt()
  UI.screenDim(0.7)
  UI.panel(190, 130, 260, 120)
  UI.title("LEAVE MATCH?", 140, 18)
  UI.button(214, 188, 100, 26, "LEAVE", {
    selected = self.promptChoice == 1, hover = self.hover == "leave", font = UI.font(8, true),
  })
  UI.button(326, 188, 100, 26, "STAY", {
    selected = self.promptChoice == 2, hover = self.hover == "stay", font = UI.font(8, true),
  })
  UI.small("ESC STAY", 0, 224, UI.C.cream2, "center")
end

function NetMatch:draw()
  Sky.draw()
  self:drawWorld()
  if self.localPlane and self.localPlane.alive and not self.spectator then
    VisionOverlay.draw(self.localPlane, self.camera, self.clouds)
  end
  self:drawHud()
  if self.leavePrompt then self:drawLeavePrompt() end
  self:drawChat()
end

function NetMatch:requestJoinNext()
  if self.spectator and self.phase == "prep" and not self.joinQueued then
    self.client:send({ type = "join_match" })
    self.joinQueued = true
  end
end

function NetMatch:leaveMatch()
  self.client:send({ type = "leave" })
  self.client.matchActive = false
  self.exited = true
  App:pop()
end

function NetMatch:sendChat()
  local text = self.chatText:gsub("^%s+", ""):gsub("%s+$", "")
  if text ~= "" then self.client:send({ type = "chat", text = text }) end
  self.chatText = ""
  self.chatOpen = false
end

function NetMatch:textinput(text)
  if self.chatOpen and #self.chatText < 80 then self.chatText = self.chatText .. text end
end

function NetMatch:drawChat()
  if self.chatOpen then
    UI.set(UI.C.ink, 0.72)
    love.graphics.rectangle("fill", 0, 0, 640, 360)
    UI.panel(120, 92, 400, 176)
    UI.small("CHAT / ENTER SEND / ESC CLOSE", 136, 104, UI.C.orange)
    local start = math.max(1, #self.chatLog - 6)
    for i = start, #self.chatLog do
      local m = self.chatLog[i]
      UI.small((m.name .. ": " .. m.text):sub(1, 62), 136, 126 + (i - start) * 14,
        UI.C.cream2, "left", 368)
    end
    UI.set(UI.C.ink3)
    love.graphics.rectangle("fill", 136, 232, 368, 20)
    UI.set(UI.C.cream)
    love.graphics.setFont(UI.font(8))
    love.graphics.print(self.chatText .. "|", 142, 238)
  elseif self.chatTimer > 0 and #self.chatLog > 0 then
    local m = self.chatLog[#self.chatLog]
    UI.set(UI.C.ink, 0.78)
    love.graphics.rectangle("fill", 20, 334, 600, 18)
    UI.small((m.name .. ": " .. m.text):sub(1, 74), 28, 338, UI.C.cream2)
  end
end

function NetMatch:keypressed(key)
  if self.chatOpen then
    if key == "escape" then
      self.chatOpen = false
      self.chatText = ""
    elseif key == "backspace" then
      self.chatText = self.chatText:sub(1, -2)
    elseif key == "return" or key == "kpenter" then
      self:sendChat()
    end
    return
  end
  if (key == "return" or key == "kpenter") and not self.leavePrompt then
    self.chatOpen = true
    self.chatText = ""
    return
  end
  if self.leavePrompt then
    if key == "escape" then
      self.leavePrompt = false
    elseif key == "left" or key == "a" then
      self.promptChoice = 1
    elseif key == "right" or key == "d" then
      self.promptChoice = 2
    elseif key == "return" or key == "kpenter" then
      if self.promptChoice == 1 then
        self:leaveMatch()
      else
        self.leavePrompt = false
      end
    end
    return
  end

  if key == "escape" then
    self.leavePrompt = true
    self.promptChoice = 2
  elseif key == "j" then
    self:requestJoinNext()
  elseif self.spectator or (self.localPlane and not self.localPlane.alive) then
    if key == "[" or key == "left" then
      self:cycleSpectator(-1)
    elseif key == "]" or key == "right" then
      self:cycleSpectator(1)
    end
  end
end

function NetMatch:mousepressed(x, y)
  local mx, my = View.toVirtual(x, y)
  if self.leavePrompt then
    if UI.hit(mx, my, 214, 188, 100, 26) then
      self:leaveMatch()
    elseif UI.hit(mx, my, 326, 188, 100, 26) then
      self.leavePrompt = false
    end
    return
  end
  if self.spectator and self.phase == "prep" and not self.joinQueued
    and UI.hit(mx, my, 244, 300, 152, 24) then
    self:requestJoinNext()
  end
end

return NetMatch


