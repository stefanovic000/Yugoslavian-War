local util = require("src.core.util")

local cases = {}

local function near(a, b, eps, msg)
  eps = eps or 0.0001
  assert(math.abs(a - b) <= eps, (msg or "values differ") .. string.format(" (%f vs %f)", a, b))
end

cases[#cases + 1] = {
  name = "clamp",
  fn = function()
    assert(util.clamp(5, 0, 3) == 3)
    assert(util.clamp(-1, 0, 3) == 0)
    assert(util.clamp(2, 0, 3) == 2)
  end,
}

cases[#cases + 1] = {
  name = "lerp and damp",
  fn = function()
    near(util.lerp(10, 20, 0.5), 15)
    near(util.damp(0, 10, 1000, 0.1), 10, 0.001)
    assert(util.damp(0, 10, 0, 1) == 0)
  end,
}

cases[#cases + 1] = {
  name = "wrapAngle and angleDiff",
  fn = function()
    near(util.wrapAngle(math.pi * 2.5), math.pi * 0.5)
    near(util.wrapAngle(-math.pi * 1.5), math.pi * 0.5)
    near(util.angleDiff(0.1, -0.1), -0.2)
    near(util.angleDiff(math.pi - 0.1, -math.pi + 0.1), 0.2)
  end,
}

cases[#cases + 1] = {
  name = "distance helpers",
  fn = function()
    near(util.dist(0, 0, 3, 4), 5)
    assert(util.dist2(0, 0, 3, 4) == 25)
    near(util.segmentPointDist2(0, 5, -10, 0, 10, 0), 25)
    near(util.segmentPointDist2(-20, 0, -10, 0, 10, 0), 100)
    near(util.segmentPointDist2(20, 0, -10, 0, 10, 0), 100)
  end,
}

cases[#cases + 1] = {
  name = "comma formatting",
  fn = function()
    assert(util.comma(0) == "0")
    assert(util.comma(999) == "999")
    assert(util.comma(1000) == "1,000")
    assert(util.comma(1234567) == "1,234,567")
    assert(util.comma(-1234) == "-1,234")
  end,
}

cases[#cases + 1] = {
  name = "splitArgs",
  fn = function()
    local a = util.splitArgs('spawn 3 "near player" \'x y\'')
    assert(#a == 4, "expected 4 args, got " .. #a)
    assert(a[1] == "spawn" and a[2] == "3" and a[3] == "near player" and a[4] == "x y")
    assert(#util.splitArgs("") == 0)
  end,
}

cases[#cases + 1] = {
  name = "wrapText",
  fn = function()
    local fakeFont = { getWidth = function(_, s) return #s * 10 end }
    local lines = util.wrapText(fakeFont, "one two three four", 70)
    assert(#lines == 3, "expected 3 lines, got " .. #lines)
    assert(lines[1] == "one two")
    assert(lines[2] == "three")
    assert(lines[3] == "four")

    local long = util.wrapText(fakeFont, "abcdefghij", 30)
    assert(#long == 4, "expected 4 chunks, got " .. #long)

    local indented = util.wrapText(fakeFont, "  alpha beta gamma", 200)
    assert(indented[1] == "  alpha beta gamma", "indentation should be preserved")
  end,
}

return cases
