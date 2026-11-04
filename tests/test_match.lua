local C = require("shared.constants")
local Match = require("server.match")

local cases = {}

cases[#cases + 1] = {
  name = "five rounds reach prep and champion",
  fn = function()
    local m = Match.new({ { id = 1, name = "A" }, { id = 2, name = "B" } }, 42)
    assert(m.round == 1 and m.phase == "round")
    assert(#m.players == 2)
    assert(m.sim:getPlane(1) and m.sim:getPlane(2))

    for round = 1, C.ROUNDS do
      m.scores[1].roundKills = C.ROUND_KILLS
      m:stepRound(C.TICK)
      if round < C.ROUNDS then
        assert(m.phase == "break", "expected break after round " .. round)
        m.breakTime = 0.001
        m:update(0.01)
        assert(m.round == round + 1, "round did not advance")
      end
    end

    assert(m.phase == "prep", "expected prep after round 5")
    assert(m.prepTime > 9, "prep should be about 10 seconds")
    assert(m.champion ~= nil, "champion missing")
    assert(m:buildSnapshot().champion ~= nil)
    m.prepTime = 0.001
    assert(m:update(0.01) == "finished", "prep should finish the old match")
  end,
}

cases[#cases + 1] = {
  name = "inputs are clamped and acked",
  fn = function()
    local m = Match.new({ { id = 1, name = "A" }, { id = 2, name = "B" } }, 7)
    m:queueInput(1, { seq = 1, throttle = 5, pitch = -9, fire = true })
    local st = m.inputs[1]
    assert(#st.queue == 1)
    assert(st.queue[1].throttle == 1)
    assert(st.queue[1].pitch == -1)
    m:stepRound(C.TICK)
    assert(st.ack == 1)
    local snap = m:buildSnapshot()
    local found = false
    for _, p in ipairs(snap.planes) do
      if p.id == 1 then found = p.ack == 1 end
    end
    assert(found, "snapshot missing ack")
  end,
}

cases[#cases + 1] = {
  name = "first pilot to the kill target wins the round",
  fn = function()
    local m = Match.new({ { id = 1, name = "A" }, { id = 2, name = "B" } }, 9)
    m.scores[2].roundKills = C.ROUND_KILLS
    m:stepRound(C.TICK)
    assert(m.phase == "break" or m.phase == "prep")
    assert(m.roundWinner == 2, "pilot with kill target should win")
  end,
}

cases[#cases + 1] = {
  name = "removing a pilot ends a short match",
  fn = function()
    local m = Match.new({ { id = 1, name = "A" }, { id = 2, name = "B" } }, 11)
    assert(m:removePlayer(2) == false)
    assert(#m.players == 1)
    assert(m.sim:getPlane(2) == nil)
  end,
}

cases[#cases + 1] = {
  name = "dead pilots respawn during the round",
  fn = function()
    local m = Match.new({ { id = 1, name = "A" }, { id = 2, name = "B" } }, 12)
    local p = m.sim:getPlane(1)
    p.alive = false
    p.hp = 0
    m.respawns[1] = 0.01
    m:stepRound(0.02)
    assert(p.alive, "dead pilot did not respawn")
    assert(p.hp == C.PLANE.hp, "respawn did not restore hull")
    assert(m.respawns[1] == nil, "respawn timer was not cleared")
  end,
}

cases[#cases + 1] = {
  name = "snapshots carry authoritative cloud positions",
  fn = function()
    local m = Match.new({ { id = 1, name = "A" }, { id = 2, name = "B" } }, 21)
    local before = m.sim.clouds.list[1].x
    m.sim.clouds.list[1].x = (before + 7) % C.WORLD.w
    local snap = m:buildSnapshot()
    assert(#snap.clouds == #m.sim.clouds.list, "cloud count mismatch")
    assert(math.abs(snap.clouds[1].x - m.sim.clouds.list[1].x) <= 0.05,
      "snapshot cloud position mismatch")
    for _, p in ipairs(snap.planes) do
      assert(type(p.hidden) == "boolean", "plane hidden state missing")
      assert(type(p.heat) == "number" and type(p.jam) == "number",
        "gun heat state missing from snapshot")
    end
  end,
}

cases[#cases + 1] = {
  name = "three players use the triangle spawn layout",
  fn = function()
    local m = Match.new({ { id = 1, name = "A" }, { id = 2, name = "B" }, { id = 3, name = "C" } }, 22)
    for i, id in ipairs(m.players) do
      local p = m.sim:getPlane(id)
      local slot = C.SPAWNS3[i]
      assert(math.abs(p.x - slot.x) < 0.1 and math.abs(p.y - slot.y) < 0.1,
        "three-player spawn does not match triangle slot " .. i)
    end
  end,
}

cases[#cases + 1] = {
  name = "snapshots carry per-viewer visibility",
  fn = function()
    local m = Match.new({ { id = 1, name = "A" }, { id = 2, name = "B" } }, 23)
    m.sim.clouds.list = {}
    local a, b = m.sim:getPlane(1), m.sim:getPlane(2)
    a.x, a.y, a.angle = 300, 250, 0
    b.x, b.y, b.angle = 650, 250, math.pi
    local snap = m:buildSnapshot()
    local byId = {}
    for _, p in ipairs(snap.planes) do byId[p.id] = p end
    assert(#byId[1].seenBy >= 1 and #byId[2].seenBy >= 1,
      "seenBy lists missing")
    local function contains(list, id)
      for _, v in ipairs(list) do if v == id then return true end end
      return false
    end
    assert(contains(byId[1].seenBy, 1) and contains(byId[2].seenBy, 2),
      "plane cannot see itself")
    assert(contains(byId[1].seenBy, 2) and contains(byId[2].seenBy, 1),
      "clear frontal view should be visible to both pilots")
  end,
}

return cases
