-- server/match.lua
-- Authoritative 5-round match. Runs at 60 Hz; clients receive 20 Hz snapshots.

local C = require("shared.constants")
local Flight = require("shared.flight")
local Sim = require("shared.sim")
local Clouds = require("shared.clouds")

local Match = {}
Match.__index = Match

local SLOTS = C.SPAWNS

local function r2(v)
  return math.floor(v * 10 + 0.5) / 10
end

local function neutral(plane)
  return { throttle = plane and plane.throttle or 0.7, pitch = 0, fire = false, seq = 0 }
end

function Match.new(players, seed)
  local m = setmetatable({
    players = {},
    info = {},
    scores = {},
    inputs = {},
    sim = Sim.new({ seed = seed }),
    seed = seed,
    round = 0,
    phase = "round",
    breakTime = 0,
    prepTime = 0,
    events = {},
    champion = nil,
    roundWinner = nil,
    respawns = {},
  }, Match)

  Clouds.avoidPoints(m.sim.clouds, SLOTS, 80)

  for i, p in ipairs(players) do
    m:addPlayer(p.id, p.name, i)
  end
  m:startRound(1)
  return m
end

function Match:addPlayer(id, name, index)
  if self.info[id] then return end
  self.players[#self.players + 1] = id
  self.info[id] = { id = id, name = name or ("Pilot" .. id), slot = index or #self.players }
  self.scores[id] = { wins = 0, kills = 0, roundKills = 0 }
  self.inputs[id] = { queue = {}, last = nil, ack = 0 }
end

function Match:removePlayer(id)
  for i, pid in ipairs(self.players) do
    if pid == id then
      table.remove(self.players, i)
      break
    end
  end
  self.info[id] = nil
  self.scores[id] = nil
  self.inputs[id] = nil
  self.respawns[id] = nil
  self.sim:removePlane(id)
  return #self.players >= 2
end

function Match:startRound(number)
  self.round = number
  self.phase = "round"
  self.roundWinner = nil

  self.sim:resetBullets()
  self.sim:resetPickups()
  self.respawns = {}

  for i, id in ipairs(self.players) do
    local slot = SLOTS[((i - 1) % #SLOTS) + 1]
    local plane = self.sim:getPlane(id)
    if not plane then
      plane = self.sim:addPlane({
        id = id, x = slot.x, y = slot.y, angle = slot.angle,
        speed = 120, throttle = 0.7, name = self.info[id].name,
        team = id, hp = C.PLANE.hp,
      })
    else
      Flight.reset(plane, slot.x, slot.y, slot.angle)
      plane.throttle = 0.7
      plane.invuln = 2
    end
    plane.throttle = 0.7
    plane.invuln = 2
    self.scores[id].roundKills = 0
    self.inputs[id].queue = {}
    self.inputs[id].last = nil
    self.inputs[id].ack = 0
  end

  self.events[#self.events + 1] = {
    type = "round_start", round = number,
  }
end

function Match:queueInput(id, msg)
  local st = self.inputs[id]
  if not st or self.phase ~= "round" then return end

  local seq = tonumber(msg.seq)
  if not seq or seq < 0 then return end
  if seq <= st.ack then return end

  local input = {
    seq = math.floor(seq),
    throttle = math.max(0, math.min(1, tonumber(msg.throttle) or 0.7)),
    pitch = math.max(-1, math.min(1, tonumber(msg.pitch) or 0)),
    fire = msg.fire == true,
  }
  if #st.queue >= 8 then table.remove(st.queue, 1) end
  st.queue[#st.queue + 1] = input
end

function Match:finishRound(winner)
  self.roundWinner = winner
  if winner and self.scores[winner] then
    self.scores[winner].wins = self.scores[winner].wins + 1
  end

  self.events[#self.events + 1] = {
    type = "round_end", round = self.round, winner = winner,
  }

  if self.round >= C.ROUNDS then
    local bestId, bestWins, bestKills = nil, -1, -1
    for id, score in pairs(self.scores) do
      if score.wins > bestWins or (score.wins == bestWins and score.kills > bestKills) then
        bestId, bestWins, bestKills = id, score.wins, score.kills
      end
    end
    self.champion = bestId
    self.phase = "prep"
    self.prepTime = C.PREP_TIME
    self.events[#self.events + 1] = {
      type = "match_end", champion = bestId, scores = self.scores,
    }
  else
    self.phase = "break"
    self.breakTime = C.ROUND_BREAK
  end
end

function Match:aliveCount()
  local n = 0
  for _, id in ipairs(self.players) do
    local p = self.sim:getPlane(id)
    if p and p.alive then n = n + 1 end
  end
  return n
end

function Match:respawnPlane(id)
  local plane = self.sim:getPlane(id)
  if not plane then return end
  local index
  for i, pid in ipairs(self.players) do
    if pid == id then index = i; break end
  end
  if not index then return end
  local slot = SLOTS[((index - 1) % #SLOTS) + 1]
  Flight.reset(plane, slot.x, slot.y, slot.angle)
  plane.throttle = 0.7
  plane.invuln = 2
  local st = self.inputs[id]
  if st then
    st.queue = {}
    st.last = nil
  end
  self.events[#self.events + 1] = {
    type = "respawn", id = id, x = slot.x, y = slot.y, angle = slot.angle,
  }
end

function Match:stepRound(dt)
  for id in pairs(self.respawns) do
    self.respawns[id] = self.respawns[id] - dt
    if self.respawns[id] <= 0 then
      self.respawns[id] = nil
      self:respawnPlane(id)
    end
  end

  local inputs = {}
  for _, id in ipairs(self.players) do
    local st = self.inputs[id]
    local plane = self.sim:getPlane(id)
    local input = table.remove(st.queue, 1) or st.last or neutral(plane)
    if input.seq and input.seq > st.ack then st.ack = input.seq end
    st.last = input
    inputs[id] = input
  end

  local events = self.sim:step(inputs, dt)
  for _, e in ipairs(events) do
    self.events[#self.events + 1] = e
    if e.type == "kill" then
      if e.killer and self.scores[e.killer] then
        self.scores[e.killer].kills = self.scores[e.killer].kills + 1
        self.scores[e.killer].roundKills = self.scores[e.killer].roundKills + 1
      end
      if e.victim and self.scores[e.victim] and self.respawns[e.victim] == nil then
        self.respawns[e.victim] = C.PLANE.respawnTime
      end
    elseif e.type == "crash" then
      if e.victim and self.scores[e.victim] and self.respawns[e.victim] == nil then
        self.respawns[e.victim] = C.PLANE.respawnTime
      end
    end
  end

  local winner
  for _, id in ipairs(self.players) do
    local score = self.scores[id]
    if score and score.roundKills >= C.ROUND_KILLS then
      if not winner or score.roundKills > self.scores[winner].roundKills then
        winner = id
      end
    end
  end
  if winner then
    self:finishRound(winner)
  end
end

function Match:update(dt)
  if self.phase == "round" then
    self:stepRound(dt)
  elseif self.phase == "break" then
    self.breakTime = self.breakTime - dt
    if self.breakTime <= 0 then
      self:startRound(self.round + 1)
    end
  elseif self.phase == "prep" then
    self.prepTime = self.prepTime - dt
    if self.prepTime <= 0 then
      return "finished"
    end
  end
  return nil
end

function Match:timer()
  if self.phase == "break" then return self.breakTime end
  if self.phase == "prep" then return self.prepTime end
  return 0
end

function Match:buildSnapshot()
  local planes = {}
  for _, id in ipairs(self.players) do
    local p = self.sim:getPlane(id)
    if p then
      planes[#planes + 1] = {
        id = id,
        x = r2(p.x), y = r2(p.y),
        vx = r2(p.vx), vy = r2(p.vy),
        a = r2(p.angle),
        pv = r2(p.pitchVel or 0),
        heat = r2(p.heat or 0),
        jam = r2(p.jammed or 0),
        hp = math.floor(p.hp),
        alive = p.alive,
        hidden = Clouds.pointInside(self.sim.clouds, p.x, p.y),
        throttle = r2(p.throttle),
        ammo = p.ammo,
        parts = {
          engine = math.floor(p.parts.engine),
          wing = math.floor(p.parts.wing),
          tail = math.floor(p.parts.tail),
          guns = math.floor(p.parts.guns),
        },
        ack = self.inputs[id] and self.inputs[id].ack or 0,
      }
    end
  end

  local bullets = {}
  for _, b in ipairs(self.sim.bullets) do
    bullets[#bullets + 1] = {
      x = r2(b.x), y = r2(b.y), vx = r2(b.vx), vy = r2(b.vy), owner = b.owner,
    }
  end

  local pickups = {}
  for _, p in ipairs(self.sim.pickups) do
    pickups[#pickups + 1] = { x = r2(p.x), y = r2(p.y), vy = r2(p.vy) }
  end

  local clouds = {}
  for _, c in ipairs(self.sim.clouds.list) do
    clouds[#clouds + 1] = { x = r2(c.x), y = r2(c.y) }
  end

  local scores = {}
  for id, score in pairs(self.scores) do
    scores[#scores + 1] = {
      id = id, wins = score.wins, kills = score.kills, roundKills = score.roundKills,
    }
  end

  local respawns = {}
  for id, t in pairs(self.respawns) do
    respawns[#respawns + 1] = { id = id, t = r2(t) }
  end

  local events = self.events
  self.events = {}

  return {
    type = "snapshot",
    seed = self.seed,
    round = self.round,
    phase = self.phase,
    timer = r2(self:timer()),
    champion = self.champion,
    roundWinner = self.roundWinner,
    planes = planes,
    bullets = bullets,
    pickups = pickups,
    clouds = clouds,
    scores = scores,
    respawns = respawns,
    events = events,
  }
end

return Match



