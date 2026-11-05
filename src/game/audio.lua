-- Tiny procedural combat audio. No external sound files: every cue is a short
-- generated waveform so the game stays a single, portable folder.

local C = require("shared.constants")
local Settings = require("src.game.settings")

local function gain()
  local d = Settings.data
  if not d then return 1 end
  return (d.masterVolume or 1) * (d.effectsVolume or 1)
end

local Audio = {
  enabled = true,
  initialized = false,
  sources = {},
  engines = {},
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
    -- OpenAL defaults vary between devices; make the listener explicit so
    -- remote engine sources actually pan left/right instead of collapsing to
    -- the centre on some Windows setups.
    pcall(love.audio.setPosition, 0, 0, 0)
    pcall(love.audio.setOrientation, 0, 0, -1, 0, 1, 0)
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

    Audio.sources.engine = build(2.0, function(t)
      -- Radial-engine thump plus prop wash. Avoid a fast tremolo or high
      -- sustained harmonics: those read as an insect buzz, not an aircraft.
      local beat = math.max(0, math.sin(2 * math.pi * 36 * t))
      local thump = (0.52 + 0.48 * beat) * (0.52 + 0.48 * beat)
      local base = math.sin(2 * math.pi * 52 * t) * 0.40
        + math.sin(2 * math.pi * 104 * t) * 0.22
        + math.sin(2 * math.pi * 156 * t) * 0.10
        + math.sin(2 * math.pi * 208 * t) * 0.04
      local wash = math.sin(2 * math.pi * 24 * t
        + 1.7 * math.sin(2 * math.pi * 2 * t)) * 0.07
      local rough = math.sin(2 * math.pi * 317 * t)
        * math.sin(2 * math.pi * 127 * t) * 0.035
      return (base * thump + wash + rough) * 0.29
    end)
    Audio.sources.engine:setLooping(true)
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
  src:setVolume(clamp((volume or 0.25) * gain(), 0, 1))
  src:setPitch(pitch or (0.94 + love.math.random() * 0.12))
  pcall(src.play, src)
end

function Audio.setEnabled(v)
  Audio.enabled = v and true or false
end

function Audio.stopEngines()
  for _, e in pairs(Audio.engines) do
    pcall(e.src.stop, e.src)
  end
  Audio.engines = {}
end

-- Continuous engine drone for a remote aircraft. It is audible even when the
-- aircraft is outside the vision cone, which is the main rear-awareness cue.
function Audio.setEngine(id, dx, dy, throttle, active, occluded)
  if not Audio.enabled then return end
  Audio.init()
  if not Audio.enabled then return end
  local e = Audio.engines[id]
  if not active then
    if e then pcall(e.src.stop, e.src); Audio.engines[id] = nil end
    return
  end
  if not e then
    e = { src = Audio.sources.engine:clone() }
    e.src:setLooping(true)
    e.src:play()
    Audio.engines[id] = e
  end
  local dist = math.sqrt(dx * dx + dy * dy)
  local vol = clamp(0.05 + (1 - dist / 700) * 0.28, 0.04, 0.32)
  if occluded then vol = vol * 0.55 end
  e.src:setVolume(clamp(vol * gain() * (Settings.data.engineVolume or 1), 0, 1))
  e.src:setPitch(0.60 + clamp(throttle or 0.6, 0, 1) * 0.45)
  -- A wider normalized x makes the stereo cue obvious even on small speakers.
  e.src:setPosition(clamp(dx / 120, -1, 1), 0, -1)
end

-- Approximate attenuation for world-space combat events.
function Audio.distanceVolume(distance, near, far)
  near, far = near or 70, far or 480
  if not distance then return 0.3 end
  return clamp(1 - (distance - near) / (far - near), 0.04, 0.7)
end

Audio.GAME_NAME = C.GAME_NAME

return Audio
