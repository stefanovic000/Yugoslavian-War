-- server/match.lua
-- Authoritative 5-round match. Runs at 60 Hz; clients receive 20 Hz snapshots.

local C = require("shared.constants")
local Flight = require("shared.flight")
local Sim = require("shared.sim")
local Clouds = require("shared.clouds")
local Vision = require("shared.vision")
local AI = require("shared.ai")

local Match = {}
Match.__index = Match

local SLOTS = C.SPAWNS

local function r2(v)
  return math.floor(v * 10 + 0.5) / 10
end

local function neutral(plane)
  return { throttle = plane and plane.throttle or 0.7, pitch = 0, fire = false, seq = 0 }
end

function Match.new(players, seed, opts)
  opts = opts or {}
  local teamMode = opts.mode == "2v2"
  local m = setmetatable({
    players = {},
    info = {},
    scores = {},
    inputs = {},
    teams = {},
    bots = {},
    aiStates = {},
    teamMode = teamMode,
    mode = opts.mode or "ffa",
    rounds = opts.rounds or C.ROUNDS,
    botDifficulty = opts.botDifficulty or "veteran",
    sidesSwapped = false,
    teamKills = { [1] = 0, [2] = 0 },
    teamWins = { [1] = 0, [2] = 0 },
    sim = Sim.new({ seed = seed, teamMode = teamMode }),
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
  Clouds.avoidPoints(m.sim.clouds, C.SPAWNS3, 80)

  for i, p in ipairs(players) do
    local team = p.team
    if not team then
      team = teamMode and (((i - 1) % 2) + 1) or p.id
    end
    m:addPlayer(p.id, p.name, i, team, p.isBot == true, p.planeType)
  end
  m:startRound(1, true)
  return m
end

function Match:addPlayer(id, name, index, team, isBot, planeType)
  if self.info[id] then return end
  self.players[#self.players + 1] = id
  self.info[id] = {
    id = id, name = name or ("Pilot" .. id), slot = index or #self.players,
    team = team or id, bot = isBot == true,
    planeType = planeType or "ik3",
  }
  self.teams[id] = team or id
  self.bots[id] = isBot == true or nil
  if isBot then self.aiStates[id] = AI.newState(self.botDifficulty) end
  self.scores[id] = {
    wins = 0, kills = 0, roundKills = 0, damage = 0, team = team or id,
  }
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
  self.teams[id] = nil
  self.bots[id] = nil
  self.aiStates[id] = nil
  self.sim:removePlane(id)
  return #self.players >= 2
end

function Match:slotFor(id, index)
  local swapped = self.sidesSwapped
  if self.mode == "1v1" then
    local left = ((index == 1) ~= swapped)
    return {
      x = left and (C.WORLD.wallLeft + 60) or (C.WORLD.wallRight - 60),
      y = 260,
      angle = left and 0 or math.pi,
    }
  end
  if self.teamMode then
    local team = self.teams[id] or 1
    local teamIndex = 0
    for _, pid in ipairs(self.players) do
      if (self.teams[pid] or 1) == team then
        teamIndex = teamIndex + 1
        if pid == id then break end
      end
    end
    local left = (team == 1) ~= swapped
    return {
      x = left and (C.WORLD.wallLeft + 60) or (C.WORLD.wallRight - 60),
      y = (teamIndex % 2 == 1) and 140 or 380,
      angle = left and 0 or math.pi,
    }
  end
  local slots = (#self.players == 3) and C.SPAWNS3 or SLOTS
  local slot = slots[((index - 1) % #slots) + 1]
  if swapped then
    return { x = C.WORLD.w - slot.x, y = slot.y, angle = slot.angle + math.pi }
  end
  return slot
end

function Match:beginRound()
  self.phase = "round"
  self.prepTime = 0
  for _, id in ipairs(self.players) do
    local p = self.sim:getPlane(id)
    -- Spawn protection was for the preparation countdown. It must not eat
    -- bullets after the round has actually started.
    if p then p.invuln = 0 end
  end
  self.events[#self.events + 1] = {
    type = "round_start", round = self.round,
  }
end

function Match:startRound(number, withPrep)
  self.round = number
  self.teamKills = { [1] = 0, [2] = 0 }
  self.phase = withPrep and "prep" or "round"
  self.prepTime = withPrep and C.ROUND_BREAK or 0
  local swapped = number > math.floor(self.rounds / 2)
  local changedSides = swapped ~= self.sidesSwapped
  self.sidesSwapped = swapped

  self.sim:resetBullets()
  self.sim:resetPickups()
  self.respawns = {}

  for i, id in ipairs(self.players) do
    local slot = self:slotFor(id, i)
    local plane = self.sim:getPlane(id)
    local team = self.teams[id] or id
    if not plane then
      plane = self.sim:addPlane({
        id = id, x = slot.x, y = slot.y, angle = slot.angle,
        speed = 120, throttle = 0.7, name = self.info[id].name,
        team = team, planeType = self.info[id].planeType,
      })
    else
      Flight.reset(plane, slot.x, slot.y, slot.angle)
      plane.throttle = 0.7
      plane.invuln = 2
      plane.team = team
    end
    plane.throttle = 0.7
    plane.invuln = 2
    plane.team = team
    self.scores[id].roundKills = 0
    self.inputs[id].queue = {}
    self.inputs[id].last = nil
    self.inputs[id].ack = 0
    if self.aiStates[id] then self.aiStates[id] = AI.newState(self.botDifficulty) end
  end

  self.events[#self.events + 1] = withPrep and {
    type = "round_prep", round = number,
  } or {
    type = "round_start", round = number,
  }
  if changedSides then
    self.events[#self.events + 1] = {
      type = "sides_switched", round = number,
    }
  end
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
    aim = tonumber(msg.aim),
    fire = msg.fire == true,
  }
  st.rtt = math.max(0, math.min(0.25, (tonumber(msg.rtt) or 0) / 1000))
  if #st.queue >= 8 then table.remove(st.queue, 1) end
  st.queue[#st.queue + 1] = input
end

function Match:finishRound(winner)
  self.roundWinner = winner
  if self.teamMode then
    local team = winner
    self.teamWins[team] = (self.teamWins[team] or 0) + 1
    for _, id in ipairs(self.players) do
      if self.teams[id] == team and self.scores[id] then
        self.scores[id].wins = self.scores[id].wins + 1
      end
    end
  elseif winner and self.scores[winner] then
    self.scores[winner].wins = self.scores[winner].wins + 1
  end

  self.events[#self.events + 1] = {
    type = "round_end", round = self.round, winner = winner,
    winnerTeam = self.teamMode and winner or nil,
  }

  if self.round >= self.rounds then
    local bestId, bestWins, bestKills = nil, -1, -1
    if self.teamMode then
      for team = 1, 2 do
        if (self.teamWins[team] or 0) > bestWins then
          bestId, bestWins = team, self.teamWins[team]
        end
      end
    else
      for id, score in pairs(self.scores) do
        if score.wins > bestWins or (score.wins == bestWins and score.kills > bestKills) then
          bestId, bestWins, bestKills = id, score.wins, score.kills
        end
      end
    end
    self.champion = bestId

    local mvp, mvpKills, mvpDamage = nil, -1, -1
    for id, score in pairs(self.scores) do
      local kills = score.kills or 0
      local damage = score.damage or 0
      if kills > mvpKills or (kills == mvpKills and damage > mvpDamage) then
        mvp, mvpKills, mvpDamage = id, kills, damage
      end
    end
    self.mvp = mvp

    self.phase = "match_end"
    self.endTime = C.ROUND_BREAK
    self.prepTime = 0
    self.events[#self.events + 1] = {
      type = "match_end", champion = bestId, mvp = mvp, scores = self.scores,
      teamMode = self.teamMode, teamWins = self.teamWins, mode = self.mode,
    }
  else
    self:startRound(self.round + 1, true)
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
  local slot = self:slotFor(id, index)
  Flight.reset(plane, slot.x, slot.y, slot.angle)
  plane.throttle = 0.7
  plane.invuln = 2
  plane.team = self.teams[id] or id
  local st = self.inputs[id]
  if st then
    st.queue = {}
    st.last = nil
  end
  self.events[#self.events + 1] = {
    type = "respawn", id = id, x = slot.x, y = slot.y, angle = slot.angle,
  }
end

function Match:enemyTarget(plane)
  local best, bestDist = nil, math.huge
  for _, pid in ipairs(self.players) do
    local other = self.sim:getPlane(pid)
    if other and other.alive and pid ~= plane.id
      and (not self.teamMode or self.teams[pid] ~= self.teams[plane.id]) then
      local dx, dy = other.x - plane.x, other.y - plane.y
      local d = dx * dx + dy * dy
      if d < bestDist then best, bestDist = other, d end
    end
  end
  return best
end

function Match:stepRound(dt)
  local inputs = {}
  for _, id in ipairs(self.players) do
    local st = self.inputs[id]
    local plane = self.sim:getPlane(id)
    local input
    if self.bots[id] and plane and plane.alive then
      input = AI.input(plane, self:enemyTarget(plane), self.sim,
        self.aiStates[id] or AI.newState(self.botDifficulty), dt, self.botDifficulty)
      input.seq = 0
    else
      input = table.remove(st.queue, 1) or st.last or neutral(plane)
      if input.seq and input.seq > st.ack then st.ack = input.seq end
      st.last = input
    end
    inputs[id] = input
  end

  self.sim.lagByOwner = {}
  for _, id in ipairs(self.players) do
    if not self.bots[id] then
      local rtt = self.inputs[id].rtt or 0.08
      -- Remote aircraft are smoothed over roughly 1/15 s on the client, on
      -- top of half the round-trip time. Compensate for both.
      self.sim.lagByOwner[id] = math.max(0, math.min(0.24, rtt * 0.5 + 0.075))
    end
  end

  local events = self.sim:step(inputs, dt)
  for _, e in ipairs(events) do
    self.events[#self.events + 1] = e
    if e.type == "hit" and e.owner and self.scores[e.owner] then
      self.scores[e.owner].damage = (self.scores[e.owner].damage or 0) + (e.damage or 0)
    elseif e.type == "kill" then
      if e.killer and self.scores[e.killer] then
        self.scores[e.killer].kills = self.scores[e.killer].kills + 1
        self.scores[e.killer].roundKills = self.scores[e.killer].roundKills + 1
        if self.teamMode then
          local team = self.teams[e.killer]
          self.teamKills[team] = (self.teamKills[team] or 0) + 1
        end
      end
    end
  end

  local winner
  if self.teamMode then
    local alive = { [1] = 0, [2] = 0 }
    for _, id in ipairs(self.players) do
      local p = self.sim:getPlane(id)
      if p and p.alive then
        local team = self.teams[id] or 1
        alive[team] = (alive[team] or 0) + 1
      end
    end
    if alive[1] == 0 or alive[2] == 0 then
      if alive[1] > 0 then winner = 1
      elseif alive[2] > 0 then winner = 2 end
    end
  else
    local alive, last = 0, nil
    for _, id in ipairs(self.players) do
      local p = self.sim:getPlane(id)
      if p and p.alive then alive = alive + 1; last = id end
    end
    if alive <= 1 then winner = last end
  end
  if winner ~= nil or (self.teamMode and self:aliveCount() == 0) then
    self:finishRound(winner)
  elseif not self.teamMode and self:aliveCount() == 0 then
    self:finishRound(nil)
  end
end

function Match:update(dt)
  if self.phase == "round" then
    self:stepRound(dt)
  elseif self.phase == "prep" then
    self.prepTime = self.prepTime - dt
    if self.prepTime <= 0 then
      self:beginRound()
    end
  elseif self.phase == "match_end" then
    self.endTime = math.max(0, (self.endTime or 0) - dt)
    if self.endTime <= 0 then return "finished" end
  elseif self.phase == "finished" then
    return "finished"
  end
  return nil
end

function Match:timer()
  if self.phase == "prep" then return self.prepTime end
  if self.phase == "match_end" then return self.endTime or 0 end
  return 0
end

function Match:buildSnapshot()
  local planes = {}
  for _, id in ipairs(self.players) do
    local p = self.sim:getPlane(id)
    if p then
      local seenBy = {}
      for _, viewerId in ipairs(self.players) do
        local viewer = self.sim:getPlane(viewerId)
        if viewer and viewer.alive
          and (viewer.id == p.id or Vision.canSee(viewer, p, self.sim.clouds)) then
          seenBy[#seenBy + 1] = viewerId
        end
      end
      planes[#planes + 1] = {
        id = id,
        x = r2(p.x), y = r2(p.y),
        vx = r2(p.vx), vy = r2(p.vy),
        a = r2(p.angle),
        pv = r2(p.pitchVel or 0),
        heat = r2(p.heat or 0),
        jam = r2(p.jammed or 0),
        hp = math.floor(p.hp),
        maxHp = math.floor(p.maxHp or p.hp),
        planeType = p.planeType or "ik3",
        alive = p.alive,
        hidden = Clouds.pointInside(self.sim.clouds, p.x, p.y),
        seenBy = seenBy,
        team = self.teams[id] or id,
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
      id = b.id,
      x = r2(b.x), y = r2(b.y), vx = r2(b.vx), vy = r2(b.vy), owner = b.owner,
      team = b.team,
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
      id = id, wins = score.wins, kills = score.kills,
      roundKills = score.roundKills, team = score.team,
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
    rounds = self.rounds,
    timer = r2(self:timer()),
    champion = self.champion,
    mvp = self.mvp,
    roundWinner = self.roundWinner,
    mode = self.mode,
    teamMode = self.teamMode,
    teamKills = self.teamKills,
    teamWins = self.teamWins,
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



