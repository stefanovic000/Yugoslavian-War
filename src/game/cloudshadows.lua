-- Soft cloud shadows on the ground strip. Purely visual; positions come from
-- the same drifting cloud list used for cover and line of sight.

local C = require("shared.constants")

local Shadows = {}

function Shadows.draw(clouds, alpha)
  if not clouds then return end
  alpha = alpha or 1
  love.graphics.push("all")
  for _, cloud in ipairs(clouds.list) do
    local a = (cloud.alpha or 0.85) * 0.10 * alpha
    local w = (cloud.r or 36) * 1.55
    love.graphics.setColor(0.03, 0.045, 0.035, a)
    love.graphics.ellipse("fill", cloud.x, C.WORLD.groundY + 3, w, 4.5, 14)
    love.graphics.setColor(0.03, 0.045, 0.035, a * 0.55)
    love.graphics.ellipse("fill", cloud.x, C.WORLD.groundY + 5, w * 1.18, 3.2, 14)
  end
  love.graphics.pop()
end

return Shadows
