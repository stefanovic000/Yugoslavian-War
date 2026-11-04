-- Shared aircraft registry. Add a plane by adding one data file here and one
-- visual definition in src/game/planeart.lua.
--
-- Stats are authoritative: both the server and client prediction use the same
-- spec. Art is deliberately separate from combat data.

local Aircraft = {}

local FILES = {
  require("shared.aircraft.ik3"),
  require("shared.aircraft.bf109e"),
}

Aircraft.DEFAULT_ID = "ik3"
Aircraft.byId = {}
Aircraft.order = {}

for _, spec in ipairs(FILES) do
  Aircraft.byId[spec.id] = spec
  Aircraft.order[#Aircraft.order + 1] = spec
end

function Aircraft.get(id)
  return Aircraft.byId[id] or Aircraft.byId[Aircraft.DEFAULT_ID]
end

function Aircraft.normalize(id)
  if Aircraft.byId[id] then return id end
  return Aircraft.DEFAULT_ID
end

function Aircraft.all()
  return Aircraft.order
end

return Aircraft
