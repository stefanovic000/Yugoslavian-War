-- cli.lua
-- Parses the command line LÖVE hands to us. Supports --flag and --key=value.

local cli = {}

function cli.parse(argv)
  local opts = { flags = {}, args = {} }
  argv = argv or {}

  for i = 1, #argv do
    local a = argv[i]
    if a:sub(1, 2) == "--" then
      local key, value = a:match("^%-%-([%w%-_]+)=(.*)$")
      if key then
        opts.flags[key] = value
      else
        key = a:match("^%-%-([%w%-_]+)$")
        if key then
          opts.flags[key] = true
        end
      end
    else
      opts.args[#opts.args + 1] = a
    end
  end

  local function on(name)
    local v = opts.flags[name]
    return v ~= nil and v ~= false and v ~= "0" and v ~= "false" and v ~= "no"
  end

  local function value(name, default)
    local v = opts.flags[name]
    if v == nil or v == true then return default end
    return v
  end

  opts.test = on("test")
  opts.smoke = on("smoke")
  opts.crash = on("crash")
  opts.debug = on("debug")
  opts.console = not on("no-console")
  opts.seed = tonumber(value("seed", nil))
  opts.logLevel = value("log", nil)
  opts.scene = value("scene", nil)
  opts.shot = value("shot", nil)
  opts.frames = tonumber(value("frames", nil))
  opts.flow = value("flow", nil)
  opts.noclouds = on("noclouds")
  opts.uitest = on("uitest")
  opts.autofire = on("autofire")
  opts.nohud = on("nohud")
  opts.server = on("server")
  return opts
end

return cli
