local controller = require("controller")
local check = require("check")

local function new(overrides)
  local opts = { press_at = 0.6, release_at = 0.4, history_seconds = 2, allow_start_in_level = false }
  for name, value in pairs(overrides or {}) do
    opts[name] = value
  end
  return controller.new(opts)
end

local function controls(overrides)
  local result = { dpad = "none", a = 0, b = 0, start = 0, select = 0 }
  for name, value in pairs(overrides) do
    result[name] = value
  end
  return result
end

local function same(actual, expected, label)
  for key, value in pairs(expected) do
    check.eq(actual[key], value, label .. " " .. key)
  end
  for key, value in pairs(actual) do
    check.eq(expected[key], value, label .. " unexpected key " .. key)
  end
end

local function list(actual, expected, label)
  check.eq(#actual, #expected, label .. " length")
  for i = 1, #expected do
    check.eq(actual[i], expected[i], label .. " " .. i)
  end
end

local RELEASED = { up = false, down = false, left = false, right = false, A = false, B = false, start = false, select = false }

return {
  { "held_frames counts from the press and is 0 once released", function()
    local pad = new()
    check.eq(pad:held_frames("a", 5), 0, "never pressed")
    pad:apply(controls({ a = 0.9 }), "playing", 10)
    check.eq(pad:held_frames("a", 25), 15, "held")
    pad:release("a", 30)
    check.eq(pad:held_frames("a", 40), 0, "released")
  end },
  { "presses a button only above press_at", function()
    local pad = new()
    pad:apply(controls({ a = 0.6 }), "playing", 1)
    same(pad:joypad(), RELEASED, "at press_at")
    pad:apply(controls({ a = 0.61 }), "playing", 2)
    same(pad:joypad(), { up = false, down = false, left = false, right = false, A = true, B = false, start = false, select = false }, "above press_at")
  end },
  { "hysteresis holds a pressed button until it drops below release_at", function()
    local pad = new()
    pad:apply(controls({ b = 0.9 }), "playing", 1)
    pad:apply(controls({ b = 0.5 }), "playing", 2)
    check.eq(pad:joypad().B, true, "held at 0.5")
    pad:apply(controls({ b = 0.4 }), "playing", 3)
    check.eq(pad:joypad().B, true, "held at release_at")
    pad:apply(controls({ b = 0.39 }), "playing", 4)
    check.eq(pad:joypad().B, false, "released below release_at")
  end },
  { "a diagonal holds two direction keys and none holds no keys", function()
    local pad = new()
    pad:apply(controls({ dpad = "up_right" }), "playing", 1)
    same(pad:joypad(), { up = true, down = false, left = false, right = true, A = false, B = false, start = false, select = false }, "up_right")
    pad:apply(controls({ dpad = "none" }), "playing", 2)
    same(pad:joypad(), RELEASED, "none")
  end },
  { "Start passes on the title screen and is forced released while playing", function()
    local pad = new()
    pad:apply(controls({ start = 1 }), "playing", 0)
    check.eq(pad:joypad().start, false, "blocked while playing")
    pad:apply(controls({ start = 1 }), "title", 60)
    check.eq(pad:joypad().start, true, "passes on title")
    pad:apply(controls({ start = 1 }), "playing", 90)
    check.eq(pad:joypad().start, false, "released on entering the level")
    local _, history = pad:describe(120)
    list(history, { "1.0 s ago: Start pressed", "0.5 s ago: Start released" }, "history")
  end },
  { "allow_start_in_level passes Start while playing", function()
    local pad = new({ allow_start_in_level = true })
    pad:apply(controls({ start = 1 }), "playing", 1)
    check.eq(pad:joypad().start, true, "start while playing")
  end },
  { "release lets go of A and records it in history", function()
    local pad = new()
    pad:apply(controls({ a = 1 }), "playing", 60)
    pad:release("a", 84)
    check.eq(pad:joypad().A, false, "A released")
    local now, history = pad:describe(90)
    check.eq(now.a, "released 0.1 s", "now.a")
    list(history, { "0.5 s ago: A pressed", "0.1 s ago: A released" }, "history")
  end },
  { "release of an already released button records nothing", function()
    local pad = new()
    pad:release("a", 30)
    local now, history = pad:describe(60)
    check.eq(now.a, "released 1.0 s", "now.a")
    list(history, {}, "history")
  end },
  { "describe reports each control's value, how long it has held, and recent changes", function()
    local pad = new()
    pad:apply(controls({ dpad = "right", a = 1 }), "playing", 30)
    local now, history = pad:describe(102)
    same(now, {
      dpad = "right for 1.2 s",
      a = "held 1.2 s",
      b = "released 1.7 s",
      start = "released 1.7 s",
      select = "released 1.7 s",
    }, "now")
    list(history, { "1.2 s ago: dpad right", "1.2 s ago: A pressed" }, "history")
  end },
  { "describe drops changes older than history_seconds", function()
    local pad = new()
    pad:apply(controls({ dpad = "right" }), "playing", 0)
    pad:apply(controls({ dpad = "left" }), "playing", 60)
    local _, history = pad:describe(120)
    list(history, { "2.0 s ago: dpad right", "1.0 s ago: dpad left" }, "at the window edge")
    _, history = pad:describe(126)
    list(history, { "1.1 s ago: dpad left" }, "past the window")
    pad:apply(controls({ dpad = "none" }), "playing", 300)
    _, history = pad:describe(300)
    list(history, { "0.0 s ago: dpad none" }, "after a later change")
  end },
  { "reset returns to the initial state and clears history", function()
    local pad = new()
    pad:apply(controls({ dpad = "down_left", a = 1, select = 1 }), "title", 10)
    local _, before = pad:describe(20)
    check.eq(#before, 3, "history before reset")
    pad:reset(30)
    same(pad:joypad(), RELEASED, "joypad")
    local now, history = pad:describe(90)
    same(now, {
      dpad = "none for 1.0 s",
      a = "released 1.0 s",
      b = "released 1.0 s",
      start = "released 1.0 s",
      select = "released 1.0 s",
    }, "now")
    list(history, {}, "history")
  end },
  { "an unchanged apply records no history and keeps since_frame", function()
    local pad = new()
    pad:apply(controls({ dpad = "right", a = 1 }), "playing", 0)
    pad:apply(controls({ dpad = "right", a = 0.5 }), "playing", 60)
    local now, history = pad:describe(120)
    check.eq(now.dpad, "right for 2.0 s", "now.dpad")
    check.eq(now.a, "held 2.0 s", "now.a")
    list(history, { "2.0 s ago: dpad right", "2.0 s ago: A pressed" }, "history")
  end },
  { "rejects a missing option and an unknown direction", function()
    local ok, err = pcall(controller.new, { press_at = 0.6, release_at = 0.4, history_seconds = 2 })
    check.eq(ok, false, "missing option fails")
    check.eq(err:match("missing option [%w_]+$"), "missing option allow_start_in_level", "missing option message")
    ok, err = pcall(function() new():apply(controls({ dpad = "diagonal" }), "playing", 1) end)
    check.eq(ok, false, "unknown direction fails")
    check.eq(err:match("unknown dpad option %a+$"), "unknown dpad option diagonal", "unknown direction message")
  end },
}
