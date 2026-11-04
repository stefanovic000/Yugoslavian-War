-- util.lua
-- Small, dependency-free helpers shared by the whole project.
-- Keep this module free of game-specific knowledge so it stays testable.

local util = {}

util.pi = math.pi
util.tau = math.pi * 2
util.huge = math.huge

local atan2 = math.atan2 or math.atan

function util.clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

function util.clamp01(v)
  return util.clamp(v, 0, 1)
end

function util.lerp(a, b, t)
  return a + (b - a) * t
end

-- Frame-rate independent exponential smoothing.
function util.damp(a, b, lambda, dt)
  return util.lerp(a, b, 1 - math.exp(-lambda * dt))
end

function util.sign(v)
  if v > 0 then return 1 end
  if v < 0 then return -1 end
  return 0
end

function util.round(v, decimals)
  local mult = 10 ^ (decimals or 0)
  return math.floor(v * mult + 0.5) / mult
end

function util.wrapAngle(a)
  a = a % (math.pi * 2)
  if a > math.pi then
    a = a - math.pi * 2
  end
  return a
end

-- Shortest signed rotation from `from` to `to`, in [-pi, pi].
function util.angleDiff(from, to)
  return util.wrapAngle(to - from)
end

function util.angleTo(x1, y1, x2, y2)
  return atan2(y2 - y1, x2 - x1)
end

function util.dist(x1, y1, x2, y2)
  local dx, dy = x2 - x1, y2 - y1
  return math.sqrt(dx * dx + dy * dy)
end

function util.dist2(x1, y1, x2, y2)
  local dx, dy = x2 - x1, y2 - y1
  return dx * dx + dy * dy
end

-- Squared distance from a point to a line segment. Used for swept bullet hits
-- so fast projectiles do not tunnel through moving targets.
function util.segmentPointDist2(px, py, x1, y1, x2, y2)
  local dx, dy = x2 - x1, y2 - y1
  local l2 = dx * dx + dy * dy
  if l2 < 1e-9 then
    return (px - x1) ^ 2 + (py - y1) ^ 2
  end
  local t = util.clamp(((px - x1) * dx + (py - y1) * dy) / l2, 0, 1)
  local qx = x1 + t * dx
  local qy = y1 + t * dy
  return (px - qx) ^ 2 + (py - qy) ^ 2
end

function util.len(x, y)
  return math.sqrt(x * x + y * y)
end

function util.norm(x, y)
  local l = math.sqrt(x * x + y * y)
  if l < 1e-9 then return 0, 0, 0 end
  return x / l, y / l, l
end

function util.approach(current, target, maxDelta)
  if current < target then
    return math.min(current + maxDelta, target)
  end
  return math.max(current - maxDelta, target)
end

local function rawRandom()
  if love and love.math then
    return love.math.random()
  end
  return math.random()
end

function util.randf(a, b)
  if a == nil then a, b = 0, 1 end
  return a + rawRandom() * (b - a)
end

function util.randi(a, b)
  if love and love.math then
    return love.math.random(a, b)
  end
  return math.random(a, b)
end

function util.chance(p)
  return rawRandom() < p
end

function util.choice(list)
  if #list == 0 then return nil end
  return list[util.randi(1, #list)]
end

function util.shuffle(list)
  for i = #list, 2, -1 do
    local j = util.randi(1, i)
    list[i], list[j] = list[j], list[i]
  end
  return list
end

function util.trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

function util.startsWith(s, prefix)
  return s:sub(1, #prefix) == prefix
end

function util.endsWith(s, suffix)
  return suffix == "" or s:sub(-#suffix) == suffix
end

function util.count(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

-- Add thousands separators: 1234567 -> "1,234,567"
function util.comma(n)
  local s = tostring(math.floor(tonumber(n) or 0))
  local sign = ""
  if s:sub(1, 1) == "-" then
    sign = "-"
    s = s:sub(2)
  end
  local out = {}
  local first = #s % 3
  if first > 0 then out[#out + 1] = s:sub(1, first) end
  for i = first + 1, #s, 3 do
    out[#out + 1] = s:sub(i, i + 2)
  end
  return sign .. table.concat(out, ",")
end

-- Split a command line into arguments, honouring single/double quotes.
function util.splitArgs(line)
  local args = {}
  local i = 1
  local n = #line
  while i <= n do
    local c = line:sub(i, i)
    if c == " " or c == "\t" then
      i = i + 1
    elseif c == '"' or c == "'" then
      local j = line:find(c, i + 1, true)
      if not j then
        args[#args + 1] = line:sub(i + 1)
        break
      end
      args[#args + 1] = line:sub(i + 1, j - 1)
      i = j + 1
    else
      local j = line:find("%s", i)
      if j then
        args[#args + 1] = line:sub(i, j - 1)
        i = j + 1
      else
        args[#args + 1] = line:sub(i)
        break
      end
    end
  end
  return args
end

-- Greedy word wrap using any font-like object exposing :getWidth(text).
-- Returns a list of display lines.
function util.wrapText(font, text, maxWidth)
  local lines = {}
  text = tostring(text)

  local function pushChunk(word)
    if word == "" then
      lines[#lines + 1] = ""
      return
    end
    local current = ""
    for ci = 1, #word do
      local ch = word:sub(ci, ci)
      if current ~= "" and font:getWidth(current .. ch) > maxWidth then
        lines[#lines + 1] = current
        current = ch
      else
        current = current .. ch
      end
    end
    if current ~= "" or #lines == 0 then
      lines[#lines + 1] = current
    end
  end

  for paragraph in (text .. "\n"):gmatch("(.-)\n") do
    if paragraph == "" then
      lines[#lines + 1] = ""
    else
      local indent = paragraph:match("^%s*") or ""
      local body = indent ~= "" and paragraph:sub(#indent + 1) or paragraph
      local firstLine = #lines + 1
      local current = ""
      for word in body:gmatch("%S+") do
        local candidate = current == "" and word or (current .. " " .. word)
        if font:getWidth(candidate) <= maxWidth then
          current = candidate
        elseif current == "" then
          pushChunk(word)
        else
          lines[#lines + 1] = current
          current = word
          if font:getWidth(current) > maxWidth then
            pushChunk(current)
            current = ""
          end
        end
      end
      if current ~= "" then lines[#lines + 1] = current end
      if indent ~= "" and lines[firstLine] then
        lines[firstLine] = indent .. lines[firstLine]
      end
    end
  end
  return lines
end

function util.truncate(font, text, maxWidth)
  text = tostring(text)
  if font:getWidth(text) <= maxWidth then return text end
  local suffix = "..."
  local lo, hi = 0, #text
  while lo < hi do
    local mid = math.floor((lo + hi + 1) / 2)
    if font:getWidth(text:sub(1, mid) .. suffix) <= maxWidth then
      lo = mid
    else
      hi = mid - 1
    end
  end
  return text:sub(1, lo) .. suffix
end

function util.now()
  if love and love.timer then return love.timer.getTime() end
  return os.clock()
end

function util.copy(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

function util.merge(dst, src)
  for k, v in pairs(src) do dst[k] = v end
  return dst
end

return util
