local json = require("vendor.dkjson")
local jev_policy = require("jev_policy")
local check = require("check")

local function observation()
  return {
    frames = { { png = "older", seconds_ago = 0.15 }, { png = "newer", seconds_ago = 0 } },
    controller_now = { dpad = "right, held 1.2 s", a = "released 0.9 s" },
    controller_history = { "1.1 s ago: A pressed", "0.9 s ago: A released" },
    progress_recently = "moved_right",
    stuck = false,
    in_air = true,
    screen = "playing",
  }
end

return {
  { "each frame references its own image asset", function()
    local request = jev_policy.build(observation())
    local frames = request.state.frames
    check.eq(#frames, 2, "frame count")
    check.eq(frames[1].taken, "0.15 seconds ago", "older frame label")
    check.eq(frames[2].taken, "now", "newer frame label")
    check.eq(request.assets[frames[1].image].data_base64, "b2xkZXI=", "older frame asset")
    check.eq(request.assets[frames[2].image].data_base64, "bmV3ZXI=", "newer frame asset")
  end },
  { "state carries the observation's named fields", function()
    local state = jev_policy.build(observation()).state
    check.eq(state.controller_now.dpad, "right, held 1.2 s", "controller_now")
    check.eq(state.controller_history[2], "0.9 s ago: A released", "controller_history")
    check.eq(state.progress_recently, "moved_right", "progress_recently")
    check.eq(state.stuck, false, "stuck")
    check.eq(state.in_air, true, "in_air")
    check.eq(state.screen, "playing", "screen")
  end },
  { "asks one Choice for the direction pad and a Noul per button and diagnostic", function()
    local questions = jev_policy.build(observation()).questions
    check.eq(questions.dpad.type, "choice", "dpad type")
    for _, list in ipairs({ jev_policy.BUTTONS, jev_policy.DIAGNOSTICS }) do
      for _, question in ipairs(list) do
        check.eq(questions[question[1]].type, "noul", question[1] .. " type")
      end
    end
  end },
  { "direction pad options are encoded in DPAD order", function()
    local encoded = json.encode(jev_policy.build(observation()).questions.dpad.criteria)
    local last = 0
    for _, option in ipairs(jev_policy.DPAD) do
      local at = encoded:find('"' .. option[1] .. '":', 1, true)
      assert(at and at > last, option[1] .. " is out of order in " .. encoded)
      last = at
    end
  end },
  { "decode returns the chosen direction and button probabilities", function()
    local controls = jev_policy.decode({
      dpad = { type = "choice", choice = "right", confidence = 0.8 },
      a = { type = "noul", noul = 0.7 },
      b = { type = "noul", noul = 0.6 },
      start = { type = "noul", noul = 0.1 },
      select = { type = "noul", noul = 0.0 },
      gap_ahead = { type = "noul", noul = 0.9 },
    })
    check.eq(controls.dpad, "right", "dpad")
    check.eq(controls.a, 0.7, "a")
    check.eq(controls.b, 0.6, "b")
    check.eq(controls.start, 0.1, "start")
    check.eq(controls.select, 0.0, "select")
    check.eq(controls.gap_ahead, nil, "diagnostics are not controls")
  end },
}
