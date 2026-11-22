-- Browser transport bridge.
-- love.js does not provide LuaSocket. The web page exposes a small JS bridge:
--   DF_WS_INIT <saveDir>   set the FS directory used for the inbound queue
--   DF_WS_SEND <json>      send one JSON line over the WebSocket
-- The JS bridge writes inbound lines to <saveDir>/ws_in and state to
-- <saveDir>/ws_state.

local WebTransport = {}
WebTransport.__index = WebTransport

function WebTransport.new()
  local self = setmetatable({
    state = "connecting",
    lines = {},
    saveDir = love.filesystem.getSaveDirectory(),
  }, WebTransport)
  print("DF_WS_INIT " .. self.saveDir)
  return self
end

function WebTransport:send(encoded)
  if encoded:find("[\r\n]") then return false end
  print("DF_WS_SEND " .. encoded)
  return true
end

function WebTransport:readState()
  local state = love.filesystem.read("ws_state")
  if state then
    state = state:gsub("%s+$", "")
    if state ~= "" then self.state = state end
  end
end

function WebTransport:readLines()
  local data = love.filesystem.read("ws_in")
  if not data or data == "" then return end
  love.filesystem.remove("ws_in")
  for line in data:gmatch("[^\n]+") do
    if line ~= "" then self.lines[#self.lines + 1] = line end
  end
end

function WebTransport:update()
  self:readState()
  self:readLines()
end

function WebTransport:takeLines()
  local out = self.lines
  self.lines = {}
  return out
end

function WebTransport:close()
  self.state = "closed"
  print("DF_WS_CLOSE")
end

return WebTransport
