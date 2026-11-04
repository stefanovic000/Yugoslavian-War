local C = require("shared.constants")
local Match = require("server.match")

local cases = {}

cases[#cases + 1] = {
  name = "five rounds use prep and finish to lobby",
  fn = function()
    local m = Match.new({ { id = 1, name = "A" }, { id = 2, name = "B" } }, 42)
    assert(m.round == 1 and m.phase == "prep")
    assert(#m.players == 2)
    assert(m.sim:getPlane(1) and m.sim:getPlane(2))
    m:update(C.ROUND_BREAK + 0.01)
    assert(m.phase == "round", "round 1 did not begin after prep")

    for round = 1, C.ROUNDS do
      m.sim:getPlane(2).alive = false
      m:stepRound(C.TICK)
      if round < C.ROUNDS then
        assert(m.phase == "prep", "expected prep after round " .. round)
        assert(m.prepTime > 2.5, "prep should be about 3 seconds")
        m:update(C.ROUND_BREAK + 0.01)
        assert(m.round == round + 1, "round did not advance")
        assert(m.phase == "round", "round did not begin after prep")
      end
    end

    assert(m.phase == "finished", "match should finish after round 5")
    assert(m.champion ~= nil, "champion missing")
    assert(m:buildSnapshot().champion ~= nil)
    assert(m:update(0.01) == "finished", "finished match should return finished")
  end,
}

cases[#cases + 1] = {
  name = "inputs are clamped and acked",
  fn = function()
    local m = Match.new({ { id = 1, name = "A" }, { id = 2, name = "B" } }, 7)
    m:beginRound()
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
  name = "last pilot flying wins the round",
  fn = function()
    local m = Match.new({ { id = 1, name = "A" }, { id = 2, name = "B" } }, 9)
    m:beginRound()
    m.sim:getPlane(2).alive = false
    m:stepRound(C.TICK)
    assert(m.phase == "prep" or m.phase == "finished")
    assert(m.roundWinner == 1, "last pilot should win the round")
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
  name = "a dead pilot stays down until the next round",
  fn = function()
    local m = Match.new({
      { id = 1, name = "A" }, { id = 2, name = "B" }, { id = 3, name = "C" },
    }, 12)
    m:beginRound()
    local p1, p2, p3 = m.sim:getPlane(1), m.sim:getPlane(2), m.sim:getPlane(3)
    p1.alive, p1.hp = false, 0
    m:stepRound(0.02)
    assert(not p1.alive, "pilot respawned inside the round")
    assert(m.phase == "round", "round should continue with two pilots alive")
    p2.alive, p3.alive = false, false
    m:stepRound(0.02)
    assert(m.phase == "prep", "all pilots down should end the round")
    m:update(C.ROUND_BREAK + 0.01)
    assert(p1.alive and p2.alive and p3.alive, "next round did not reset the planes")
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

cases[#cases + 1] = {
  name = "2v2 teams and bots are authoritative",
  fn = function()
    local m = Match.new({
      { id = 1, name = "A", team = 1 },
      { id = -1, name = "BOT 1", isBot = true, team = 2 },
    }, 26, { mode = "2v2" })
    assert(m.teamMode, "2v2 mode was not enabled")
    local human, bot = m.sim:getPlane(1), m.sim:getPlane(-1)
    assert(human and bot, "team planes missing")
    assert(human.team == 1 and bot.team == 2, "team assignment mismatch")
    assert(human.x < bot.x, "teams should spawn on opposite sides")
    m.sim.clouds.list = {}
    m:stepRound(C.TICK)
    assert(bot.vx ~= 0 or bot.vy ~= 0, "bot AI did not produce movement")

    m.teamKills[1] = C.ROUND_KILLS
    bot.alive = false
    m:stepRound(C.TICK)
    assert(m.roundWinner == 1, "team 1 should win the round")
    assert(m.scores[1].wins == 1, "team member did not receive the win")
    assert(m.phase ~= "round", "round did not end")
  end,
}

cases[#cases + 1] = {
  name = "1v1 starts with preparation and opposite spawns",
  fn = function()
    local m = Match.new({
      { id = 1, name = "A", team = 1 },
      { id = 2, name = "B", team = 2 },
    }, 27, { mode = "1v1" })
    assert(m.mode == "1v1" and not m.teamMode)
    assert(m.phase == "prep" and m.prepTime > 2.5)
    local a, b = m.sim:getPlane(1), m.sim:getPlane(2)
    assert(a.x < b.x, "1v1 pilots should start on opposite sides")
    m:update(C.ROUND_BREAK + 0.01)
    assert(m.phase == "round")
  end,
}

return cases
