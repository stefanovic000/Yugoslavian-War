local Class = require("src.core.class")

local cases = {}

cases[#cases + 1] = {
  name = "class construction",
  fn = function()
    local Thing = Class("Thing")
    function Thing:init(a, b)
      self.a, self.b = a, b
    end

    local t = Thing.new(1, 2)
    assert(t.a == 1 and t.b == 2)
    assert(Class.is(t, Thing))
    assert(tostring(t) == "Thing")
  end,
}

cases[#cases + 1] = {
  name = "inheritance",
  fn = function()
    local Base = Class("Base")
    function Base:init(x)
      self.x = x
    end
    function Base:value()
      return self.x
    end

    local Child = Class("Child", Base)
    function Child:init(x, y)
      Base.init(self, x)
      self.y = y
    end
    function Child:sum()
      return self.x + self.y
    end

    local c = Child.new(2, 3)
    assert(c:value() == 2)
    assert(c:sum() == 5)
    assert(Class.is(c, Child))
    assert(Class.is(c, Base))
    assert(not Class.is(Base.new(1), Child))
    assert(tostring(c) == "Child")
  end,
}

return cases
