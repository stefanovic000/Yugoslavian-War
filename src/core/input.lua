-- input.lua
-- Action-map input. Physical keys are tracked once, actions are derived, and
-- pressed/released edges are cleared at the end of every frame.

local input = {
  actions = {},
  keyActions = {},
  keysDown = {},
  pressed = {},
  released = {},
  mouseDown = {},
  mousePressed = {},
  mouseReleased = {},
  enabled = true,
}

local function addAction(action, key)
  input.keyActions[key] = input.keyActions[key] or {}
  table.insert(input.keyActions[key], action)
end

function input.bind(action, keys)
  if type(keys) == "string" then keys = { keys } end
  input.actions[action] = keys
  for _, key in ipairs(keys) do
    addAction(action, key)
  end
end

function input.bindMany(bindings)
  for action, keys in pairs(bindings) do
    input.bind(action, keys)
  end
end

function input.keypressed(key, isrepeat)
  if not key then return end
  input.keysDown[key] = true
  if isrepeat then return end
  local list = input.keyActions[key]
  if list then
    for _, action in ipairs(list) do
      input.pressed[action] = true
    end
  end
end

function input.keyreleased(key)
  input.keysDown[key] = nil
  local list = input.keyActions[key]
  if not list then return end
  for _, action in ipairs(list) do
    local stillDown = false
    for _, k in ipairs(input.actions[action] or {}) do
      if input.keysDown[k] then
        stillDown = true
        break
      end
    end
    if not stillDown then
      input.released[action] = true
    end
  end
end

function input.mousepressed(button)
  input.mouseDown[button] = true
  input.mousePressed[button] = true
end

function input.mousereleased(button)
  input.mouseDown[button] = nil
  input.mouseReleased[button] = true
end

function input.isDown(action)
  if not input.enabled then return false end
  for _, key in ipairs(input.actions[action] or {}) do
    if input.keysDown[key] then return true end
  end
  return false
end

function input.wasPressed(action)
  if not input.enabled then return false end
  return input.pressed[action] == true
end

function input.wasReleased(action)
  if not input.enabled then return false end
  return input.released[action] == true
end

function input.axis(negativeAction, positiveAction)
  local v = 0
  if input.isDown(negativeAction) then v = v - 1 end
  if input.isDown(positiveAction) then v = v + 1 end
  return v
end

function input.keyDown(key)
  return input.keysDown[key] == true
end

function input.keyPressed(key)
  -- Intended for keys not mapped to actions (debug/menu keys).
  return input.keysDown[key] == true
end

function input.mouseIsDown(button)
  return input.mouseDown[button] == true
end

function input.mouseWasPressed(button)
  return input.mousePressed[button] == true
end

function input.endFrame()
  input.pressed = {}
  input.released = {}
  input.mousePressed = {}
  input.mouseReleased = {}
end

function input.reset()
  input.keysDown = {}
  input.mouseDown = {}
  input.endFrame()
end

return input
