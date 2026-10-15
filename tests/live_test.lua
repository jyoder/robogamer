local image = require("image")
local png = require("png")
local typesafe = require("typesafe")
local jev_policy = require("jev_policy")
local check = require("check")

local function fill(img, x0, y0, x1, y1, r, g, b)
  for y = y0, y1 do
    for x = x0, x1 do
      image.set(img, x, y, r, g, b)
    end
  end
end

-- A 256x240 frame shaped like the NES screen: sky, ground, and a red block standing in for Mario.
local function frame_png(mario_x)
  local img = image.new(256, 240)
  fill(img, 0, 0, 255, 207, 92, 148, 252)
  fill(img, 0, 208, 255, 239, 200, 76, 12)
  fill(img, mario_x, 192, mario_x + 15, 207, 216, 40, 0)
  return png.encode(image.upscale(img, 2))
end

local VALID_DPAD = {}
for _, option in ipairs(jev_policy.DPAD) do
  VALID_DPAD[option[1]] = true
end

return {
  { "a game-shaped request round-trips through Jev on one reused connection", function()
    local client = typesafe.client({ model = "jev-preview" })
    local request = jev_policy.build({
      frames = { { png = frame_png(56), seconds_ago = 0.15 }, { png = frame_png(64), seconds_ago = 0 } },
      controller_now = { dpad = "right, held 1.2 s", a = "released", b = "held 1.2 s", start = "released", select = "released" },
      controller_history = { "1.2 s ago: right pressed", "1.2 s ago: B pressed" },
      progress_recently = "moved_right",
      stuck = false,
      in_air = false,
      screen = "playing",
    })
    for attempt = 1, 2 do
      local response, err = client:systemone(request)
      assert(response, err)
      local controls = jev_policy.decode(response.answers)
      assert(VALID_DPAD[controls.dpad], "attempt " .. attempt .. ": unexpected dpad " .. tostring(controls.dpad))
      for _, button in ipairs(jev_policy.BUTTONS) do
        local p = controls[button[1]]
        assert(p >= 0 and p <= 1, "attempt " .. attempt .. ": " .. button[1] .. " probability " .. tostring(p))
      end
      check.eq(response.model:match("^jev%-"), "jev-", "response model")
    end
  end },
  { "API errors come back as nil and a message", function()
    local client = typesafe.client({ model = "no-such-model" })
    local response, err = client:systemone({ state = "x", questions = { q = { type = "noul", instructions = "Is `state` x?" } } })
    check.eq(response, nil, "response")
    assert(err:match("^HTTP 4%d%d"), "expected an HTTP 4xx error, got " .. tostring(err))
  end },
}
