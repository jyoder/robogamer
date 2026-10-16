-- Turns Super Mario Bros RAM into named game facts and tracks Mario's horizontal progress.
local telemetry = {}

local RAM = {
  x_page = 0x006D,
  x_offset = 0x0086,
  x_speed = 0x0057,
  y_speed = 0x009F,
  float_state = 0x001D,
  mode = 0x0770,
  player_state = 0x000E,
  y_page = 0x00B5,
  lives = 0x075A,
  world = 0x075F,
  level = 0x0760,
}

local SCREENS = { [0] = "title", [1] = "playing", [2] = "playing", [3] = "game_over" }
local JUMP_FLOAT, LEDGE_FLOAT = 1, 2
local FLAGPOLE_FLOAT = 3
local DYING_STATES = { [0x0B] = true, [0x06] = true }
local LOWEST_ONSCREEN_Y_PAGE = 1

local function signed(byte)
  return byte >= 128 and byte - 256 or byte
end

-- readbyte: function(address) -> number, memory.readbyte in FCEUX.
-- x_speed is positive moving right; walking tops out near 24 and running near 40.
-- y_speed is negative while Mario rises.
function telemetry.read(readbyte)
  return {
    x = readbyte(RAM.x_page) * 256 + readbyte(RAM.x_offset),
    x_speed = signed(readbyte(RAM.x_speed)),
    y_speed = signed(readbyte(RAM.y_speed)),
    float_state = readbyte(RAM.float_state),
    mode = readbyte(RAM.mode),
    player_state = readbyte(RAM.player_state),
    y_page = readbyte(RAM.y_page),
    lives = readbyte(RAM.lives),
    world = readbyte(RAM.world),
    level = readbyte(RAM.level),
  }
end

local function death_cause(snapshot)
  if DYING_STATES[snapshot.player_state] then
    return "enemy"
  elseif snapshot.y_page > LOWEST_ONSCREEN_Y_PAGE then
    return "pit"
  end
end

function telemetry.facts(snapshot)
  local cause = death_cause(snapshot)
  local in_air = snapshot.float_state == JUMP_FLOAT or snapshot.float_state == LEDGE_FLOAT
  return {
    screen = SCREENS[snapshot.mode],
    in_air = in_air,
    jumped = snapshot.float_state == JUMP_FLOAT,
    descending = in_air and snapshot.y_speed >= 0,
    dying = cause ~= nil,
    death_cause = cause,
    level_complete = snapshot.float_state == FLAGPOLE_FLOAT,
  }
end

local Tracker = {}
Tracker.__index = Tracker

-- opts: { window_frames, stuck_frames, min_progress }, all required.
function telemetry.tracker(opts)
  for _, key in ipairs({ "window_frames", "stuck_frames", "min_progress" }) do
    assert(type(opts[key]) == "number", "telemetry.tracker: opts." .. key .. " is required")
  end
  return setmetatable({
    window_frames = opts.window_frames,
    stuck_frames = opts.stuck_frames,
    min_progress = opts.min_progress,
    horizon = math.max(opts.window_frames, opts.stuck_frames),
    samples = {},
  }, Tracker)
end

function Tracker:push(frame, x)
  local samples = self.samples
  samples[#samples + 1] = { frame = frame, x = x }
  -- Keeps the newest sample at or before the horizon as the baseline for both windows.
  while samples[2] and samples[2].frame <= frame - self.horizon do
    table.remove(samples, 1)
  end
end

local function sample_at_or_before(samples, frame)
  local found = samples[1]
  for _, sample in ipairs(samples) do
    if sample.frame > frame then
      break
    end
    found = sample
  end
  return found
end

function Tracker:progress_recently(frame)
  local samples = self.samples
  if #samples == 0 then
    return "no_progress"
  end
  local delta = samples[#samples].x - sample_at_or_before(samples, frame - self.window_frames).x
  if delta > self.min_progress then
    return "moved_right"
  elseif delta < -self.min_progress then
    return "moved_left"
  end
  return "no_progress"
end

function Tracker:stuck(frame)
  local samples = self.samples
  local start = frame - self.stuck_frames
  if #samples == 0 or samples[1].frame > start then
    return false
  end
  local start_x = sample_at_or_before(samples, start).x
  local max_x = start_x
  for _, sample in ipairs(samples) do
    if sample.frame > start and sample.frame <= frame then
      max_x = math.max(max_x, sample.x)
    end
  end
  return max_x - start_x <= self.min_progress
end

function Tracker:reset()
  self.samples = {}
end

return telemetry
