-- Shared ground-height function. The client draws this exact crest and the
-- server uses it for crash checks, so visuals and collision agree.

local C = require("shared.constants")

local Terrain = {}

function Terrain.height(x)
  return math.floor(C.WORLD.groundY + 2
    + math.sin(x * 0.035 + 0.3) * 3
    + math.sin(x * 0.091 + 0.6) * 1.05)
end

return Terrain
