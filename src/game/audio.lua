-- Tiny procedural combat audio. No external sound files: every cue is a short
-- generated waveform so the game stays a single, portable folder.

local C = require("shared.constants")

local Audio = {
  enabled = true,
  initialized = false,
  sources = {},
}

local function clamp(x, lo, hi)
  return math.max(lo, math.min(hi, x))
end

local function build(duration, fn)
  local rate = 22050
  local samples = math.max(1, math.floor(duration * rate))
  local data = love.sound.newSoundData(samples, rate, 16, 1)
  for i = 0, samples - 1 do
    local t = i / rate
    data:setSample(i, clamp(fn(t, duration), -1, 1))
  end
  return love.audio.newSource(data, "static")
end

function Audio.init()
  if Audio.initialized then return end
  Audio.initialized = true
  local ok, err = pcall(function()
    local random = love.math.random

    Audio.sources.shot = build(0.055, function(t, d)
      local env = 1 - t / d
      local noise = random() * 2 - 1
      local thump = math.sin(2 * math.pi * (150 - 700 * t) * t)
      return (noise * 0.55 + thump * 0.45) * env * 0.30
    end)

    Audio.sources.hit = build(0.09, function(t, d)
      local env = (1 - t / d) ^ 2
      return (math.sin(2 * math.pi * 1250 * t) * 0.55
        + math.sin(2 * math.pi * 1870 * t) * 0.25) * env * 0.24
    end)

    Audio.sources.explosion = build(0.45, function(t, d)
      local env = (1 - t / d) ^ 1.6
      local noise = random() * 2 - 1
      local low = math.sin(2 * math.pi * 55 * t) * 0.35
      return (noise * 0.8 + low) * env * 0.55
    end)

    Audio.sources.overheat = build(0.4, function(t, d)
      local env = (1 - t / d)
      local hiss = random() * 2 - 1
      local click = (t < 0.03) and math.sin(2 * math.pi * 90 * t) * 0.8 or 0
      return (hiss * 0.25 + click) * env * 0.28
    end)

    Audio.sources.stall = build(0.24, function(t, d)
      local env = math.sin(math.pi * t / d)
      return math.sin(2 * math.pi * 420 * t) * env * 0.20
    end)

    Audio.sources.respawn = build(0.28, function(t, d)
      local env = math.sin(math.pi * t / d)
      local f = 260 + 500 * (t / d)
      return math.sin(2 * math.pi * f * t) * env * 0.18
    end)

    Audio.sources.pickup = build(0.16, function(t, d)
      local env = math.sin(math.pi * t / d)
      local f = 700 + 900 * (t / d)
      return math.sin(2 * math.pi * f * t) * env * 0.18
    end)

    Audio.sources.ram = build(0.18, function(t, d)
      local env = (1 - t / d) ^ 2
      return (random() * 2 - 1) * env * 0.30
    end)
  end)
  if not ok then
    Audio.enabled = false
    Audio.error = tostring(err)
  end
end

function Audio.play(name, volume, pitch)
  if not Audio.enabled then return end
  Audio.init()
  if not Audio.enabled then return end
  local base = Audio.sources[name]
  if not base then return end
  local src = base:clone()
  src:setVolume(clamp(volume or 0.25, 0, 1))
  src:setPitch(pitch or (0.94 + love.math.random() * 0.12))
  pcall(src.play, src)
end

function Audio.setEnabled(v)
  Audio.enabled = v and true or false
end

-- Approximate attenuation for world-space combat events.
function Audio.distanceVolume(distance, near, far)
  near, far = near or 70, far or 480
  if not distance then return 0.3 end
  return clamp(1 - (distance - near) / (far - near), 0.04, 0.7)
end

Audio.GAME_NAME = C.GAME_NAME

return Audio
