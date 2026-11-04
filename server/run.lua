-- Standalone Ubuntu server entry point.
-- Usage: lua5.1 server/run.lua [--port=7777] [--host=0.0.0.0]

package.path = "./?.lua;./?/init.lua;" .. package.path

local Server = require("server.server")

local port, host = 7777, "0.0.0.0"
for _, a in ipairs(arg or {}) do
  local p = a:match("^%-%-port=(%d+)$")
  local h = a:match("^%-%-host=(.+)$")
  if p then port = tonumber(p) end
  if h then host = h end
end

local server = Server.new({ port = port, host = host })
server:run()
