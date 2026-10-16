local telemetry = require("telemetry")
local check = require("check")

local function snapshot(fields)
  local s = { x = 0, y_speed = 0, float_state = 0, mode = 1, player_state = 0x08, y_page = 1, lives = 2, world = 0, level = 0 }
  for key, value in pairs(fields) do
    s[key] = value
  end
  return s
end

local function tracker()
  return telemetry.tracker({ window_frames = 30, stuck_frames = 90, min_progress = 4 })
end

local function push_flat(t, from, to, x)
  for frame = from, to do
    t:push(frame, x)
  end
end

return {
  { "read names each RAM value and combines the x page and offset", function()
    local memory = {
      [0x006D] = 2, [0x0086] = 0x10, [0x001D] = 1, [0x0770] = 1, [0x000E] = 0x08,
      [0x00B5] = 1, [0x075A] = 3, [0x075F] = 0, [0x0760] = 2, [0x0057] = 0, [0x009F] = 0,
    }
    local s = telemetry.read(function(address) return memory[address] end)
    check.eq(s.x, 528, "x")
    check.eq(s.float_state, 1, "float_state")
    check.eq(s.mode, 1, "mode")
    check.eq(s.player_state, 0x08, "player_state")
    check.eq(s.y_page, 1, "y_page")
    check.eq(s.lives, 3, "lives")
    check.eq(s.world, 0, "world")
    check.eq(s.level, 2, "level")
  end },
  { "read gives x_speed a sign, negative moving left", function()
    local speed = 0x28
    local function readbyte(address)
      return address == 0x0057 and speed or 0
    end
    check.eq(telemetry.read(readbyte).x_speed, 40, "running right")
    speed = 0xF0
    check.eq(telemetry.read(readbyte).x_speed, -16, "moving left")
  end },
  { "read gives y_speed a sign, negative rising", function()
    local speed = 0xFB
    local function readbyte(address)
      return address == 0x009F and speed or 0
    end
    check.eq(telemetry.read(readbyte).y_speed, -5, "rising")
    speed = 0x03
    check.eq(telemetry.read(readbyte).y_speed, 3, "falling")
  end },
  { "descending is true in the air once Mario stops rising", function()
    check.eq(telemetry.facts(snapshot({ float_state = 1, y_speed = -4 })).descending, false, "rising")
    check.eq(telemetry.facts(snapshot({ float_state = 1, y_speed = 0 })).descending, true, "at the top")
    check.eq(telemetry.facts(snapshot({ float_state = 2, y_speed = 2 })).descending, true, "off a ledge")
    check.eq(telemetry.facts(snapshot({ float_state = 0, y_speed = 0 })).descending, false, "on the ground")
  end },
  { "jumped tells a jump from walking off a ledge", function()
    check.eq(telemetry.facts(snapshot({ float_state = 1 })).jumped, true, "jump")
    check.eq(telemetry.facts(snapshot({ float_state = 2 })).jumped, false, "ledge")
  end },
  { "facts maps each game mode to a screen", function()
    check.eq(telemetry.facts(snapshot({ mode = 0 })).screen, "title", "mode 0")
    check.eq(telemetry.facts(snapshot({ mode = 1 })).screen, "playing", "mode 1")
    check.eq(telemetry.facts(snapshot({ mode = 2 })).screen, "playing", "mode 2")
    check.eq(telemetry.facts(snapshot({ mode = 3 })).screen, "game_over", "mode 3")
  end },
  { "in_air is true only while jumping or falling", function()
    check.eq(telemetry.facts(snapshot({ float_state = 0 })).in_air, false, "float 0")
    check.eq(telemetry.facts(snapshot({ float_state = 1 })).in_air, true, "float 1")
    check.eq(telemetry.facts(snapshot({ float_state = 2 })).in_air, true, "float 2")
    check.eq(telemetry.facts(snapshot({ float_state = 3 })).in_air, false, "float 3")
  end },
  { "dying covers the dying and dead states and falling into a pit", function()
    check.eq(telemetry.facts(snapshot({ player_state = 0x0B })).dying, true, "dying state")
    check.eq(telemetry.facts(snapshot({ player_state = 0x06 })).dying, true, "dead state")
    check.eq(telemetry.facts(snapshot({ player_state = 0x08, y_page = 2 })).dying, true, "below the screen")
    check.eq(telemetry.facts(snapshot({ player_state = 0x08, y_page = 1 })).dying, false, "normal on screen")
  end },
  { "death_cause tells an enemy hit from a fall into a pit", function()
    check.eq(telemetry.facts(snapshot({ player_state = 0x0B, y_page = 1 })).death_cause, "enemy", "hit")
    check.eq(telemetry.facts(snapshot({ player_state = 0x08, y_page = 2 })).death_cause, "pit", "fall")
    check.eq(telemetry.facts(snapshot({ player_state = 0x08, y_page = 1 })).death_cause, nil, "alive")
  end },
  { "level_complete is true only on the flagpole", function()
    check.eq(telemetry.facts(snapshot({ float_state = 0 })).level_complete, false, "float 0")
    check.eq(telemetry.facts(snapshot({ float_state = 1 })).level_complete, false, "float 1")
    check.eq(telemetry.facts(snapshot({ float_state = 2 })).level_complete, false, "float 2")
    check.eq(telemetry.facts(snapshot({ float_state = 3 })).level_complete, true, "float 3")
  end },
  { "progress needs more than min_progress in either direction", function()
    local cases = {
      { 104, "no_progress" }, { 105, "moved_right" }, { 96, "no_progress" }, { 95, "moved_left" },
    }
    for _, case in ipairs(cases) do
      local t = tracker()
      t:push(0, 100)
      t:push(30, case[1])
      check.eq(t:progress_recently(30), case[2], "x 100 to " .. case[1])
    end
  end },
  { "progress compares against the newest sample at least a window old", function()
    local t = tracker()
    t:push(0, 0)
    t:push(10, 100)
    t:push(40, 103)
    check.eq(t:progress_recently(40), "no_progress", "baseline is frame 10, not frame 0")
  end },
  { "progress falls back to the oldest sample when history is shorter than the window", function()
    local t = tracker()
    t:push(0, 100)
    t:push(10, 110)
    check.eq(t:progress_recently(10), "moved_right", "baseline is frame 0")
  end },
  { "stuck is false until history covers stuck_frames", function()
    local t = tracker()
    check.eq(t:stuck(0), false, "no samples")
    push_flat(t, 0, 89, 100)
    check.eq(t:stuck(89), false, "89 frames of history")
  end },
  { "stuck is true when x stays flat for stuck_frames", function()
    local t = tracker()
    push_flat(t, 0, 90, 100)
    check.eq(t:stuck(90), true, "flat for 90 frames")
  end },
  { "stuck tolerates jitter up to min_progress", function()
    local t = tracker()
    push_flat(t, 0, 45, 100)
    push_flat(t, 46, 90, 104)
    check.eq(t:stuck(90), true, "rose exactly min_progress")
  end },
  { "stuck is false when Mario made progress inside the span", function()
    local t = tracker()
    push_flat(t, 0, 50, 100)
    push_flat(t, 51, 90, 110)
    check.eq(t:stuck(90), false, "advanced 10 px")
  end },
  { "stuck ignores progress from before the span", function()
    local t = tracker()
    push_flat(t, 0, 20, 0)
    push_flat(t, 21, 200, 300)
    check.eq(t:stuck(200), true, "flat for the last 180 frames")
  end },
  { "reset clears history", function()
    local stalled = tracker()
    push_flat(stalled, 0, 90, 100)
    check.eq(stalled:stuck(90), true, "stuck before reset")
    stalled:reset()
    check.eq(stalled:stuck(90), false, "stuck after reset")

    local t = tracker()
    t:push(0, 100)
    t:push(30, 200)
    check.eq(t:progress_recently(30), "moved_right", "progress before reset")
    t:reset()
    check.eq(t:progress_recently(30), "no_progress", "progress after reset")
    t:push(100, 50)
    t:push(130, 60)
    check.eq(t:progress_recently(130), "moved_right", "fresh history after reset")
  end },
}
