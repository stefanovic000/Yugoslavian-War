-- src/net/client.lua
-- Non-blocking TCP/JSON client. One connection per game session; scenes read
-- messages from a queue.

local json = require("lib.json")
local C = require("shared.constants")
local IS_WEB = love.system.getOS() == "Web"
local socket = not IS_WEB and require("socket") or nil
local WebTransport = IS_WEB and require("src.net.webtransport") or nil

local Client = {}
Client.__index = Client

local MAX_OUTBOX = 65536
local MAX_BUFFER = 32768
local CONNECT_TIMEOUT = 6
local IDLE_TIMEOUT = 20

local function now()
  if IS_WEB then return love.timer.getTime() end
  return socket.gettime()
end

function Client.new()
  return setmetatable({
    sock = nil,
    status = "idle",
    messages = {},
    buffer = "",
    outbox = "",
    selfId = nil,
    name = nil,
    host = nil,
    port = nil,
    errorMessage = nil,
    lastRecv = 0,
    lastPing = 0,
    pingAt = nil,
    rtt = 0,
    jitter = 0,
    connectingAt = 0,
    serverVersion = nil,
  }, Client)
end

function Client:send(message)
  if self.status ~= "connected" and self.status ~= "connecting" then return false end
  if self.web then
    local ok, encoded = pcall(json.encode, message)
    if not ok then return false end
    return self.web:send(encoded)
  end
  if not self.sock then return false end
  local ok, encoded = pcall(json.encode, message)
  if not ok then return false end
  self.outbox = self.outbox .. encoded .. "\n"
  if #self.outbox > MAX_OUTBOX then
    self:close("Network buffer overflow.")
    return false
  end
  return true
end

function Client:connect(host, port, name, aircraft)
  self:close()
  self.host, self.port, self.name = host, port, name
  self.aircraft = aircraft or self.aircraft or "ik3"
  self.status = "connecting"
  self.selfId = nil
  self.serverVersion = nil
  self.connectingAt = now()
  self.messages = {}
  self.buffer, self.outbox = "", ""
  self.errorMessage = nil

  if IS_WEB then
    self.web = WebTransport.new()
    self.sock = nil
    return true
  end

  local sock, err = socket.tcp()
  if not sock then
    self.status = "error"
    self.errorMessage = "Could not create socket."
    return false
  end
  sock:settimeout(0)
  local ok, cerr = sock:connect(host, port)
  if not ok and cerr ~= "timeout" and cerr ~= "Operation already in progress" then
    sock:close()
    self.status = "error"
    self.errorMessage = "Could not connect to " .. tostring(host) .. ":" .. tostring(port) .. "."
    return false
  end
  self.sock = sock
  return true
end

function Client:connected()
  if self.status ~= "connected" then
    self.status = "connected"
    self.lastRecv = now()
    self:send({ type = "hello", name = self.name, version = C.VERSION,
      aircraft = self.aircraft or "ik3" })
  end
end

function Client:flush()
  if not self.sock or self.outbox == "" then return end
  local sent, err, last = self.sock:send(self.outbox)
  if sent then
    self.outbox = self.outbox:sub(sent + 1)
  elseif err == "timeout" then
    self.outbox = self.outbox:sub((last or 0) + 1)
  else
    self:close("Connection lost.")
  end
end

function Client:handleLine(line)
  if line == "" then return end
  if #line > 65536 then
    self:close("Invalid server data.")
    return
  end
  local ok, msg = pcall(json.decode, line)
  if ok and type(msg) == "table" and type(msg.type) == "string" then
    if msg.type == "welcome" then
      self.selfId = msg.selfId
      self.name = msg.name or self.name
      self.serverVersion = msg.version
    elseif msg.type == "pong" and self.pingAt then
      local sample = math.max(0, math.min(0.3, now() - self.pingAt))
      self.jitter = self.rtt > 0 and math.abs(sample - self.rtt) or 0
      self.rtt = self.rtt > 0 and (self.rtt * 0.75 + sample * 0.25) or sample
      self.pingAt = nil
    end
    self.messages[#self.messages + 1] = msg
  end
end

function Client:read()
  if not self.sock then return end
  local data, err, partial = self.sock:receive(4096)
  local chunk = data or partial
  if chunk and #chunk > 0 then
    self.buffer = self.buffer .. chunk
    self.lastRecv = now()
  end

  if err == "closed" then
    self:close("Server closed the connection.")
    return
  elseif err and err ~= "timeout" then
    self:close("Connection error.")
    return
  end

  if #self.buffer > MAX_BUFFER and not self.buffer:find("\n", 1, true) then
    self:close("Invalid server data.")
    return
  end

  while true do
    local nl = self.buffer:find("\n", 1, true)
    if not nl then break end
    local line = self.buffer:sub(1, nl - 1)
    self.buffer = self.buffer:sub(nl + 1)
    self:handleLine(line)
    if self.status == "closed" then return end
  end
end

function Client:update(dt)
  if self.status == "idle" or self.status == "error" or self.status == "closed" then
    return
  end

  local t = now()

  if self.web then
    self.web:update()
    if self.web.state == "error" then
      self:close("WebSocket connection error.")
      return
    elseif self.web.state == "closed" then
      self:close("Server closed the connection.")
      return
    end
    if self.web.state == "connected" and self.status == "connecting" then
      self:connected()
    end
    for _, line in ipairs(self.web:takeLines()) do
      self:handleLine(line)
      if self.status == "closed" then return end
    end
    if self.status == "connected" then
      self.lastPing = self.lastPing or 0
      if t - self.lastPing > 2 then
        self.lastPing = t
        self.pingAt = t
        self:send({ type = "ping", t = t })
      end
      if t - self.lastRecv > IDLE_TIMEOUT then
        self:close("Server timed out.")
      end
    elseif t - self.connectingAt > CONNECT_TIMEOUT then
      self:close("Connection timed out.")
    end
    return
  end

  if self.status == "connecting" then
    if not self.sock then return end
    local _, writable = socket.select(nil, { self.sock }, 0)
    if writable and #writable > 0 then
      local ip, err = self.sock:getpeername()
      if ip then
        self:connected()
      else
        self:close("Could not connect.")
        return
      end
    elseif t - self.connectingAt > CONNECT_TIMEOUT then
      self:close("Connection timed out.")
      return
    else
      return
    end
  end

  if not self.sock then return end

  self:read()
  if self.status ~= "connected" then return end

  self:flush()

  self.lastPing = self.lastPing or 0
  if t - self.lastPing > 2 then
    self.lastPing = t
    self.pingAt = t
    self:send({ type = "ping", t = t })
  end

  if t - self.lastRecv > IDLE_TIMEOUT then
    self:close("Server timed out.")
  end
end

function Client:takeMessages()
  local out = self.messages
  self.messages = {}
  return out
end

function Client:close(reason)
  if self.web then
    pcall(self.web.close, self.web)
    self.web = nil
  end
  if self.sock then
    pcall(self.sock.close, self.sock)
  end
  self.sock = nil
  if self.status ~= "error" and self.status ~= "closed" then
    self.status = reason and "closed" or "idle"
  end
  if reason then
    self.errorMessage = reason
    if self.status ~= "error" then self.status = "closed" end
  end
end

return Client
