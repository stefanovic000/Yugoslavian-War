-- Web-specific quality limits. Desktop LuaJIT keeps the full effects.
local WebQuality = {
  isWeb = love.system.getOS() == "Web",
}

WebQuality.particleMax = WebQuality.isWeb and 350 or 700
WebQuality.visionInterval = WebQuality.isWeb and 0.10 or 0

return WebQuality
