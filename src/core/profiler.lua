-- profiler.lua
-- Tiny named-scope profiler. Scopes are cumulative per frame; stats are
-- averaged over a rolling window so the HUD does not flicker.

local profiler = {
  enabled = true,
  maxFrames = 120,
  frames = {},
  frame = {},
  stack = {},
  frameStart = 0,
}

local function now()
  return love.timer.getTime()
end

function profiler.beginFrame()
  if not profiler.enabled then return end
  profiler.frame = {}
  profiler.stack = {}
  profiler.frameStart = now()
end

function profiler.push(name)
  if not profiler.enabled then return end
  local stack = profiler.stack
  stack[#stack + 1] = { name = name, start = now() }
end

function profiler.pop()
  if not profiler.enabled then return end
  local stack = profiler.stack
  local scope = table.remove(stack)
  if not scope then return end
  local elapsed = (now() - scope.start) * 1000
  profiler.frame[scope.name] = (profiler.frame[scope.name] or 0) + elapsed
end

function profiler.measure(name, fn)
  profiler.push(name)
  fn()
  profiler.pop()
end

function profiler.finishFrame()
  if not profiler.enabled then return end
  local frame = profiler.frame
  frame._total = (now() - profiler.frameStart) * 1000
  local frames = profiler.frames
  frames[#frames + 1] = frame
  if #frames > profiler.maxFrames then
    table.remove(frames, 1)
  end
end

function profiler.stats()
  local agg = {}
  for _, frame in ipairs(profiler.frames) do
    for name, ms in pairs(frame) do
      if name ~= "_total" then
        local a = agg[name]
        if not a then
          a = { name = name, avg = 0, max = 0, last = 0, n = 0 }
          agg[name] = a
        end
        a.avg = a.avg + ms
        a.n = a.n + 1
        a.last = ms
        if ms > a.max then a.max = ms end
      end
    end
  end

  local list = {}
  for _, a in pairs(agg) do
    a.avg = a.avg / math.max(1, a.n)
    list[#list + 1] = a
  end
  table.sort(list, function(a, b)
    if a.avg == b.avg then return a.name < b.name end
    return a.avg > b.avg
  end)
  return list
end

function profiler.reset()
  profiler.frames = {}
  profiler.frame = {}
  profiler.stack = {}
end

return profiler
