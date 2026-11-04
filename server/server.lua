-- server/server.lua
-- Authoritative, non-blocking TCP game server (LuaSocket on Ubuntu).
--
-- Security posture for an open port:
--   * bounded message/line/outbox buffers, per-client rate limits, idle timeout
--   * strict message whitelist + clamped numeric input, JSON only, no eval
--   * connection-per-IP cap, global client/room caps, room-create rate limit
--   * kicks ban the IP and client id for the lifetime of that room
--   * slow clients are disconnected instead of blocking the loop

local socket = require("socket")
local json = require("lib.json")
local C = require("shared.constants")
local Match = require("server.match")

local Server = {}
Server.__index = Server

local MAX_LINE = 4096
local MAX_BUFFER = 16384
local MAX_OUTBOX = 98304
local MAX_CLIENTS = 64
local MAX_CLIENTS_PER_IP = 6
local MAX_ROOMS = 16
local MAX_SPECTATORS = 8
local IDLE_TIMEOUT = 30
local MSG_RATE = 140
local MSG_BURST = 100

local function now()
  return socket.gettime()
end

local function sanitizeName(name, fallback)
  name = tostring(name or ""):gsub("[%c]", ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" then name = fallback or "Pilot" end
  if #name > 14 then name = name:sub(1, 14) end
  return name
end

local function sanitizeRoomName(name, fallback)
  name = tostring(name or ""):gsub("[%c]", ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" then name = fallback or "ROOM" end
  if #name > 24 then name = name:sub(1, 24) end
  return name
end

local function normalizeIp(ip)
  ip = tostring(ip or "?"):gsub("^::ffff:", "")
  return ip
end

function Server.new(opts)
  opts = opts or {}
  local self = setmetatable({}, Server)

  io.stdout:setvbuf("line")

  self.port = opts.port or 7777
  self.host = opts.host or "0.0.0.0"
  self.maxClients = opts.maxClients or MAX_CLIENTS
  self.snapInterval = 1 / C.SNAPSHOT_HZ

  self.sock = assert(socket.tcp())
  self.sock:setoption("reuseaddr", true)
  assert(self.sock:bind(self.host, self.port))
  assert(self.sock:listen(64))
  self.sock:settimeout(0)

  self.clients = {}
  self.clientOrder = {}
  self.ipCounts = {}
  self.rooms = {}
  self.roomOrder = {}
  self.nextClientId = 0
  self.nextRoomId = 0

  self.lastTime = now()
  self.tickAcc = 0
  self.snapshotAcc = 0
  self.roomsAcc = 0
  self.running = true
  self.rng = 1234567

  self:log("listening on %s:%d", self.host, self.port)
  return self
end

function Server:log(fmt, ...)
  print(string.format("[%s] " .. fmt, os.date("%Y-%m-%d %H:%M:%S"), ...))
end

function Server:randomSeed()
  self.rng = (1103515245 * self.rng + 12345) % 2147483648
  return math.floor(now() * 1000 + self.rng) % 2147483647
end

-------------------------------------------------------------------------------
-- networking
-------------------------------------------------------------------------------

function Server:accept()
  while true do
    local sock, err = self.sock:accept()
    if not sock then break end

    local ip, port = sock:getpeername()
    ip = normalizeIp(ip)
    if #self.clientOrder >= self.maxClients or (self.ipCounts[ip] or 0) >= MAX_CLIENTS_PER_IP then
      pcall(sock.close, sock)
      self:log("reject connection from %s (cap)", ip)
    else
      self.nextClientId = self.nextClientId + 1
      local client = {
        id = self.nextClientId,
        sock = sock,
        ip = ip,
        port = port,
        name = nil,
        hello = false,
        room = nil,
        buffer = "",
        outbox = "",
        tokens = MSG_BURST,
        violations = 0,
        lastRecv = now(),
        createTimes = {},
        spectator = false,
      }
      sock:settimeout(0)
      pcall(sock.setoption, sock, "tcp-nodelay", true)
      self.clients[client.id] = client
      self.clientOrder[#self.clientOrder + 1] = client.id
      self.ipCounts[ip] = (self.ipCounts[ip] or 0) + 1
    end
  end
end

function Server:send(client, message)
  if not client or client.closed then return end
  local ok, encoded = pcall(json.encode, message)
  if not ok then
    self:log("json encode failed: %s", tostring(encoded))
    return
  end
  self:sendLine(client, encoded .. "\n")
end

function Server:sendLine(client, line)
  if #line > MAX_LINE * 16 then
    self:disconnect(client, "oversized outbound message")
    return
  end
  client.outbox = client.outbox .. line
  if #client.outbox > MAX_OUTBOX then
    self:disconnect(client, "outbound backpressure")
  end
end

function Server:flushClient(client)
  if client.closed or client.outbox == "" then return end
  local sent, err, last = client.sock:send(client.outbox)
  if sent then
    client.outbox = client.outbox:sub(sent + 1)
  elseif err == "timeout" then
    client.outbox = client.outbox:sub((last or 0) + 1)
  else
    self:disconnect(client, "send error: " .. tostring(err))
  end
end

function Server:disconnect(client, reason)
  if not client or client.closed then return end
  client.closed = true
  self:leaveRoom(client, true)
  pcall(client.sock.close, client.sock)
  self.clients[client.id] = nil
  for i, id in ipairs(self.clientOrder) do
    if id == client.id then
      table.remove(self.clientOrder, i)
      break
    end
  end
  self.ipCounts[client.ip] = math.max(0, (self.ipCounts[client.ip] or 1) - 1)
  self:log("disconnect #%d %s (%s)", client.id, client.ip, reason or "")
end

function Server:readClient(client)
  local data, err, partial = client.sock:receive(4096)
  local chunk = data or partial
  if chunk and #chunk > 0 then
    client.buffer = client.buffer .. chunk
    client.lastRecv = now()
  end
  if err == "closed" then
    self:disconnect(client, "closed")
    return
  elseif err and err ~= "timeout" then
    self:disconnect(client, tostring(err))
    return
  end

  if #client.buffer > MAX_BUFFER and not client.buffer:find("\n", 1, true) then
    self:disconnect(client, "line too long")
    return
  end

  while true do
    local nl = client.buffer:find("\n", 1, true)
    if not nl then break end
    local line = client.buffer:sub(1, nl - 1)
    client.buffer = client.buffer:sub(nl + 1)
    if #line > MAX_LINE then
      self:disconnect(client, "message too large")
      return
    end
    if line ~= "" then
      self:handleLine(client, line)
    end
    if client.closed then return end
  end
end

function Server:handleLine(client, line)
  if client.tokens < 1 then
    client.violations = client.violations + 1
    if client.violations > 20 then
      self:disconnect(client, "flood")
    end
    return
  end
  client.tokens = client.tokens - 1

  local ok, msg = pcall(json.decode, line)
  if not ok or type(msg) ~= "table" or type(msg.type) ~= "string" then
    client.violations = client.violations + 1
    if client.violations > 10 then
      self:disconnect(client, "malformed messages")
    end
    return
  end

  local handler = self.handlers[msg.type]
  if not handler then
    self:send(client, { type = "error", message = "Unknown message." })
    return
  end
  handler(self, client, msg)
end

-------------------------------------------------------------------------------
-- rooms
-------------------------------------------------------------------------------

function Server:playerInfo(room)
  local list = {}
  local teamMode = room.mode == "2v2"
  for i, id in ipairs(room.players) do
    local c = self.clients[id]
    if c then
      list[#list + 1] = {
        id = id, name = c.name or ("Pilot" .. id), isBot = false,
        team = teamMode and (((i - 1) % 2) + 1) or id,
      }
    end
  end
  local humans = #list
  for b = 1, (room.bots or 0) do
    local index = humans + b
    list[#list + 1] = {
      id = -b, name = "BOT " .. tostring(b), isBot = true,
      team = teamMode and (((index - 1) % 2) + 1) or (-b),
    }
  end
  return list
end

function Server:roomState(room)
  local players = {}
  local teamMode = room.mode == "2v2"
  for i, id in ipairs(room.players) do
    local c = self.clients[id]
    if c then
      players[#players + 1] = {
        id = id, name = c.name or ("Pilot" .. id), host = (id == room.hostId),
        bot = false, team = teamMode and (((i - 1) % 2) + 1) or id,
      }
    end
  end
  local spectators = {}
  for _, id in ipairs(room.spectators) do
    local c = self.clients[id]
    if c then
      spectators[#spectators + 1] = { id = id, name = c.name or ("Pilot" .. id) }
    end
  end
  return {
    type = "room",
    room = {
      id = room.id,
      name = room.name,
      host = room.hostId,
      status = room.status,
      players = players,
      spectators = spectators,
      max = C.MAX_PLAYERS,
      bots = room.bots or 0,
      mode = room.mode or "ffa",
      round = room.match and room.match.round or 0,
      phase = room.match and room.match.phase or "lobby",
      champion = room.match and room.match.champion or nil,
    },
  }
end

function Server:roomSummary(room)
  local host = self.clients[room.hostId]
  return {
    id = room.id,
    name = room.name,
    host = room.hostId,
    hostName = host and host.name or "?",
    status = room.status,
    players = #room.players + (room.bots or 0),
    bots = room.bots or 0,
    mode = room.mode or "ffa",
    spectators = #room.spectators,
    max = C.MAX_PLAYERS,
    round = room.match and room.match.round or 0,
    phase = room.match and room.match.phase or "lobby",
  }
end

function Server:roomList()
  local list = {}
  for _, id in ipairs(self.roomOrder) do
    local room = self.rooms[id]
    if room then
      list[#list + 1] = self:roomSummary(room)
    end
  end
  return list
end

function Server:broadcastRoom(room)
  if not room then return end
  local state = self:roomState(room)
  for _, id in ipairs(room.players) do
    local c = self.clients[id]
    if c then self:send(c, state) end
  end
  for _, id in ipairs(room.spectators) do
    local c = self.clients[id]
    if c then self:send(c, state) end
  end
end

function Server:broadcastRooms()
  local list = self:roomList()
  for _, id in ipairs(self.clientOrder) do
    local c = self.clients[id]
    if c and c.hello and not c.room then
      self:send(c, { type = "rooms", rooms = list })
    end
  end
end

function Server:matchStart(room)
  local players = self:playerInfo(room)
  for _, id in ipairs(room.players) do
    local c = self.clients[id]
    if c then
      self:send(c, {
        type = "match_start",
        roomId = room.id,
        seed = room.match.seed,
        players = players,
        spectator = false,
      })
    end
  end
  for _, id in ipairs(room.spectators) do
    local c = self.clients[id]
    if c then
      self:send(c, {
        type = "match_start",
        roomId = room.id,
        seed = room.match.seed,
        players = players,
        spectator = true,
      })
    end
  end
end

function Server:startMatch(room)
  local players = self:playerInfo(room)
  room.match = Match.new(players, self:randomSeed(), { mode = room.mode })
  room.status = "playing"
  self:matchStart(room)
  self:broadcastRoom(room)
  self:broadcastRooms()
  self:log("room %d match started (%d players)", room.id, #room.players)
end

function Server:cancelMatch(room, reason)
  room.match = nil
  room.status = "lobby"
  for _, id in ipairs(room.spectators) do
    local c = self.clients[id]
    if c then
      self:send(c, { type = "match_cancelled", reason = reason or "Match ended." })
    end
  end
  for _, id in ipairs(room.players) do
    local c = self.clients[id]
    if c then
      self:send(c, { type = "match_cancelled", reason = reason or "Match ended." })
    end
  end
  self:broadcastRoom(room)
  self:broadcastRooms()
end

function Server:createRoom(client, msg)
  local t = now()
  local recent = 0
  for i = #client.createTimes, 1, -1 do
    if t - client.createTimes[i] > 60 then table.remove(client.createTimes, i) else recent = recent + 1 end
  end
  if recent >= 3 then
    self:send(client, { type = "error", message = "Too many rooms created. Wait a minute." })
    return
  end
  if #self.roomOrder >= MAX_ROOMS then
    self:send(client, { type = "error", message = "Server is full of rooms." })
    return
  end

  self:leaveRoom(client, false)
  client.createTimes[#client.createTimes + 1] = t

  self.nextRoomId = self.nextRoomId + 1
  local room = {
    id = self.nextRoomId,
    name = sanitizeRoomName(msg.name, (client.name or "Pilot") .. " ROOM"),
    hostId = client.id,
    players = { client.id },
    spectators = {},
    bots = 0,
    mode = "ffa",
    bannedIps = {},
    bannedIds = {},
    status = "lobby",
    match = nil,
  }
  self.rooms[room.id] = room
  self.roomOrder[#self.roomOrder + 1] = room.id
  client.room = room.id
  client.spectator = false

  self:send(client, { type = "joined", room = self:roomSummary(room), selfId = client.id, spectator = false })
  self:send(client, self:roomState(room))
  self:broadcastRooms()
  self:log("room %d created by #%d (%s)", room.id, client.id, room.name)
end

function Server:joinRoom(client, msg)
  local room = self.rooms[tonumber(msg.room) or -1]
  if not room then
    self:send(client, { type = "error", message = "Room no longer exists." })
    return
  end
  if room.bannedIps[client.ip] or room.bannedIds[client.id] then
    self:send(client, { type = "error", message = "You are banned from this room." })
    return
  end
  self:leaveRoom(client, false)

  local spectator = room.status ~= "lobby" or #room.players >= C.MAX_PLAYERS
  if spectator then
    if #room.spectators >= MAX_SPECTATORS then
      self:send(client, { type = "error", message = "Room spectator slots are full." })
      return
    end
    room.spectators[#room.spectators + 1] = client.id
    client.spectator = true
  else
    room.players[#room.players + 1] = client.id
    client.spectator = false
    -- A human takes priority over a reserved bot slot.
    if room.bots and #room.players + room.bots > C.MAX_PLAYERS then
      room.bots = math.max(0, C.MAX_PLAYERS - #room.players)
    end
  end
  client.room = room.id

  self:send(client, {
    type = "joined", room = self:roomSummary(room), selfId = client.id, spectator = spectator,
  })
  self:broadcastRoom(room)
  self:broadcastRooms()

  if room.match then
    self:send(client, {
      type = "match_start",
      roomId = room.id,
      seed = room.match.seed,
      players = self:playerInfo(room),
      spectator = spectator,
    })
  end
end

function Server:leaveRoom(client, silent)
  local room = client.room and self.rooms[client.room]
  client.room = nil
  client.spectator = false
  if not room then return end

  local wasPlayer = false
  for i, id in ipairs(room.players) do
    if id == client.id then
      table.remove(room.players, i)
      wasPlayer = true
      break
    end
  end
  for i, id in ipairs(room.spectators) do
    if id == client.id then
      table.remove(room.spectators, i)
      break
    end
  end

  if not silent then
    self:send(client, { type = "left" })
  end

  if room.match and wasPlayer then
    local stillEnough = room.match:removePlayer(client.id)
    if not stillEnough then
      self:cancelMatch(room, "Not enough pilots.")
    end
  end

  if #room.players == 0 then
    self:closeRoom(room, "Host left.")
    return
  end

  if room.hostId == client.id then
    room.hostId = room.players[1]
  end

  self:broadcastRoom(room)
  self:broadcastRooms()
end

function Server:closeRoom(room, reason)
  local all = {}
  for _, id in ipairs(room.players) do all[#all + 1] = id end
  for _, id in ipairs(room.spectators) do all[#all + 1] = id end
  for _, id in ipairs(all) do
    local c = self.clients[id]
    if c then
      c.room = nil
      c.spectator = false
      self:send(c, { type = "room_closed", reason = reason })
    end
  end
  self.rooms[room.id] = nil
  for i, id in ipairs(self.roomOrder) do
    if id == room.id then
      table.remove(self.roomOrder, i)
      break
    end
  end
  self:broadcastRooms()
end

function Server:kick(client, msg)
  local room = client.room and self.rooms[client.room]
  if not room or room.hostId ~= client.id then
    self:send(client, { type = "error", message = "Only the host can kick." })
    return
  end
  local targetId = tonumber(msg.target)
  if not targetId or targetId == client.id then return end
  local target = self.clients[targetId]
  if not target or target.room ~= room.id then
    self:send(client, { type = "error", message = "Player is no longer in this room." })
    return
  end

  room.bannedIps[target.ip] = true
  room.bannedIds[target.id] = true
  self:send(target, { type = "kicked", room = room.name, reason = "Kicked by the host." })
  target.room = nil
  target.spectator = false

  local wasPlayer = false
  for i, id in ipairs(room.players) do
    if id == target.id then
      table.remove(room.players, i)
      wasPlayer = true
      break
    end
  end
  for i, id in ipairs(room.spectators) do
    if id == target.id then
      table.remove(room.spectators, i)
      break
    end
  end

  if room.match and wasPlayer then
    local stillEnough = room.match:removePlayer(target.id)
    if not stillEnough then self:cancelMatch(room, "Not enough pilots.") end
  end
  if #room.players == 0 then
    self:closeRoom(room, "Host left.")
    return
  end

  self:broadcastRoom(room)
  self:broadcastRooms()
  self:log("room %d kicked #%d (%s)", room.id, target.id, target.ip)
end

-------------------------------------------------------------------------------
-- message handlers
-------------------------------------------------------------------------------

Server.handlers = {}

function Server.handlers.hello(self, client, msg)
  if client.hello then return end
  client.hello = true
  client.name = sanitizeName(msg.name, "Pilot" .. client.id)
  self:send(client, {
    type = "welcome",
    selfId = client.id,
    name = client.name,
    version = C.VERSION,
    rooms = self:roomList(),
  })
  self:log("hello #%d %s (%s)", client.id, client.name, client.ip)
end

function Server.handlers.rooms(self, client)
  if not client.hello then return end
  self:send(client, { type = "rooms", rooms = self:roomList() })
end

function Server.handlers.create(self, client, msg)
  if not client.hello then return end
  self:createRoom(client, msg)
end

function Server.handlers.join(self, client, msg)
  if not client.hello then return end
  self:joinRoom(client, msg)
end

function Server.handlers.leave(self, client)
  if not client.hello then return end
  self:leaveRoom(client, false)
end

function Server.handlers.start(self, client)
  if not client.hello then return end
  local room = client.room and self.rooms[client.room]
  if not room then return end
  if room.hostId ~= client.id then
    self:send(client, { type = "error", message = "Only the host can start." })
    return
  end
  if room.status ~= "lobby" then return end
  if #room.players + (room.bots or 0) < C.MIN_PLAYERS then
    self:send(client, { type = "error", message = "At least 2 pilots or bots are needed." })
    return
  end
  self:startMatch(room)
end

function Server.handlers.room_settings(self, client, msg)
  if not client.hello then return end
  local room = client.room and self.rooms[client.room]
  if not room or room.hostId ~= client.id or room.status ~= "lobby" then return end
  local mode = msg.mode == "2v2" and "2v2" or "ffa"
  local bots = math.floor(tonumber(msg.bots) or room.bots or 0)
  bots = math.max(0, math.min(C.MAX_PLAYERS, bots))
  bots = math.min(bots, C.MAX_PLAYERS - #room.players)
  room.mode = mode
  room.bots = bots
  self:broadcastRoom(room)
  self:broadcastRooms()
end

function Server.handlers.kick(self, client, msg)
  if not client.hello then return end
  self:kick(client, msg)
end

function Server.handlers.input(self, client, msg)
  local room = client.room and self.rooms[client.room]
  if not room or not room.match or client.spectator then return end
  room.match:queueInput(client.id, msg)
end

function Server.handlers.join_match(self, client)
  if not client.hello then return end
  local room = client.room and self.rooms[client.room]
  if not room or room.status ~= "prep" or not client.spectator then return end
  if #room.players >= C.MAX_PLAYERS then
    self:send(client, { type = "error", message = "No player slots left." })
    return
  end
  for i, id in ipairs(room.spectators) do
    if id == client.id then
      table.remove(room.spectators, i)
      break
    end
  end
  room.players[#room.players + 1] = client.id
  client.spectator = false
  self:broadcastRoom(room)
  self:send(client, { type = "joined_match" })
end

function Server.handlers.ping(self, client, msg)
  if not client.hello then return end
  self:send(client, { type = "pong", t = msg.t, serverTime = now() })
end

-------------------------------------------------------------------------------
-- loop
-------------------------------------------------------------------------------

function Server:tickMatches(dt)
  for _, roomId in ipairs(self.roomOrder) do
    local room = self.rooms[roomId]
    if room and room.match then
      local result = room.match:update(dt)
      room.status = (room.match and room.match.phase == "prep") and "prep" or "playing"

      if result == "finished" then
        if #room.players >= C.MIN_PLAYERS then
          self:startMatch(room)
        else
          self:cancelMatch(room, "Not enough pilots for another match.")
        end
      end
    end
  end
end

function Server:broadcastSnapshots()
  for _, roomId in ipairs(self.roomOrder) do
    local room = self.rooms[roomId]
    if room and room.match then
      local snap = room.match:buildSnapshot()
      snap.roomId = room.id
      snap.t = now()
      local members = {}
      for _, id in ipairs(room.players) do members[#members + 1] = id end
      for _, id in ipairs(room.spectators) do members[#members + 1] = id end
      for _, id in ipairs(members) do
        local c = self.clients[id]
        if c then self:send(c, snap) end
      end
    end
  end
end

function Server:update()
  local t = now()
  local dt = math.min(0.25, t - self.lastTime)
  self.lastTime = t

  self:accept()

  -- Read from all sockets. Non-blocking, so this is bounded by the client cap.
  for _, id in ipairs(self.clientOrder) do
    local c = self.clients[id]
    if c and not c.closed then
      self:readClient(c)
    end
  end

  -- Token bucket refill + idle timeout.
  for _, id in ipairs(self.clientOrder) do
    local c = self.clients[id]
    if c and not c.closed then
      c.tokens = math.min(MSG_BURST, c.tokens + dt * MSG_RATE)
      if t - c.lastRecv > IDLE_TIMEOUT then
        self:disconnect(c, "idle timeout")
      end
    end
  end

  -- Fixed simulation.
  self.tickAcc = self.tickAcc + dt
  local steps = 0
  while self.tickAcc >= C.TICK and steps < 12 do
    self:tickMatches(C.TICK)
    self.tickAcc = self.tickAcc - C.TICK
    steps = steps + 1
  end

  -- Network snapshots.
  self.snapshotAcc = self.snapshotAcc + dt
  if self.snapshotAcc >= self.snapInterval then
    self.snapshotAcc = self.snapshotAcc - self.snapInterval
    self:broadcastSnapshots()
  end

  -- Lobby list refresh.
  self.roomsAcc = self.roomsAcc + dt
  if self.roomsAcc >= 2 then
    self.roomsAcc = 0
    self:broadcastRooms()
  end

  for _, id in ipairs(self.clientOrder) do
    local c = self.clients[id]
    if c and not c.closed then
      self:flushClient(c)
    end
  end
end

function Server:run()
  while self.running do
    self:update()
    socket.sleep(0.001)
  end
end

function Server:close()
  self.running = false
  for _, id in ipairs(self.clientOrder) do
    local c = self.clients[id]
    if c then pcall(c.sock.close, c.sock) end
  end
  pcall(self.sock.close, self.sock)
end

return Server

