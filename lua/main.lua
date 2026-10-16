-- Runs inside FCEUX (Lua 5.1, no ffi): plays one run in real time, one frame per launcher tick.
local lua_dir = debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")
package.path = lua_dir .. "/?.lua;" .. package.path

local config = require("config")
local mailbox = require("mailbox")
local controller = require("controller")
local overlay = require("overlay")
local telemetry = require("telemetry")
local json = require("vendor.dkjson")

local run_dir = assert(os.getenv("ROBOGAMER_RUN_DIR"), "start runs with `mise run play`")
local exchange_dir = assert(os.getenv("ROBOGAMER_EXCHANGE_DIR"))
local policy = assert(os.getenv("ROBOGAMER_POLICY"))
-- Without rewinds Mario plays on his lives until the level ends or the game is over.
local rewinds = os.getenv("ROBOGAMER_REWINDS") ~= "0"

local box = mailbox.open(exchange_dir, run_dir .. "/results")
local pad = controller.new(config.controller)
local tracker = telemetry.tracker(config.tracker)
local events = assert(io.open(run_dir .. "/events.jsonl", "w"))
events:setvbuf("line")

local frame = 0
local function log(event)
  event.frame = frame
  events:write(json.encode(event), "\n")
end

local oldest_frame_ago = math.max(unpack(config.frames_ago))
local shots, has_shot = {}, {}
local posted_frame = {}
local seq, applied_seq, applied_frame = 0, 0, 0
local applied_result

local DEATH_TEXT = { pit = "fell into a pit", enemy = "was hit by an enemy" }
local deaths_seen = {}

local function died_near(x)
  local memory = config.death_memory
  local near = {}
  for i = #deaths_seen, 1, -1 do
    local death = deaths_seen[i]
    if death.x >= x - memory.behind and death.x <= x + memory.ahead and #near < memory.keep then
      table.insert(near, 1, DEATH_TEXT[death.cause])
    end
  end
  return near
end

local function post_job(facts, x)
  -- true reads the emulator's own frame, without the overlay drawn on top of it.
  box:write_frame(frame, gui.gdscreenshot(true))
  shots[#shots + 1] = frame
  has_shot[frame] = true
  while shots[1] < frame - oldest_frame_ago - config.max_staleness_frames do
    local old = table.remove(shots, 1)
    has_shot[old] = nil
    box:remove_frame(old)
  end

  local frames = {}
  for _, ago in ipairs(config.frames_ago) do
    if has_shot[frame - ago] then
      frames[#frames + 1] = { frame = frame - ago, seconds_ago = ago / config.fps }
    end
  end
  local controller_now, controller_history = pad:describe(frame)
  seq = seq + 1
  posted_frame[seq] = frame
  box:post_job({
    seq = seq,
    frame = frame,
    frames = frames,
    controller_now = controller_now,
    controller_history = controller_history,
    progress_recently = tracker:progress_recently(frame),
    stuck = tracker:stuck(frame),
    in_air = facts.in_air,
    screen = facts.screen,
    died_near_here = died_near(x),
  })
end

-- Applies the newest answer still fresh enough; older ones are superseded by it.
local function apply_answers(facts)
  local s = seq
  while s > applied_seq and posted_frame[s] >= frame - config.max_staleness_frames do
    local result = box:read_result(s)
    if result then
      applied_seq = s
      if result.controls then
        pad:apply(result.controls, facts.screen, frame)
        applied_frame, applied_result = frame, result
        log({ type = "applied", seq = s, age = frame - result.frame })
      end
      return
    end
    s = s - 1
  end
  if frame - applied_frame > config.answer_timeout_frames then
    pad:release("a", frame)
  end
end

-- Mario only jumps on a fresh press of A, and holding A only lengthens a jump while he rises. So A is
-- let go on the way down and pressed again on landing if Jev's latest answer still wants a jump.
local function rearm_jump(facts, landed)
  if facts.descending or (not facts.in_air and pad:held_frames("a", frame) > config.grounded_a_frames) then
    pad:release("a", frame)
  elseif landed and applied_result and frame - applied_frame <= config.answer_timeout_frames then
    pad:apply(applied_result.controls, facts.screen, frame)
  end
end

-- The title screen only starts the game on a fresh press of Start, so a held Start becomes taps.
local function retap_start()
  if pad:held_frames("start", frame) > config.start_tap_frames then
    pad:release("start", frame)
  end
end

local function baseline(facts)
  pad:apply({
    dpad = "right",
    a = frame % 60 < 20 and 1 or 0,
    b = 1,
    start = facts.screen == "title" and frame % 30 < 5 and 1 or 0,
    select = 0,
  }, facts.screen, frame)
end

local function joypad_for(facts)
  local keys = pad:joypad()
  -- The title screen ignores Start while any other button is held.
  if facts.screen == "title" and keys.start then
    return { start = true }
  end
  return keys
end

local checkpoint_frames = math.floor(config.checkpoint_seconds * config.fps)
local checkpoints = {}
local saved_frame, deaths_since_save = 0, 0

-- Only saves while Mario stands alive on the ground, so no savestate is mid-fall into a pit.
local function save_checkpoint(facts)
  if not rewinds or facts.screen ~= "playing" or facts.dying or facts.in_air or frame - saved_frame < checkpoint_frames then
    return
  end
  local state = savestate.create()
  savestate.save(state)
  checkpoints[#checkpoints + 1] = state
  if #checkpoints > 2 then
    table.remove(checkpoints, 1)
  end
  saved_frame, deaths_since_save = frame, 0
end

local function rewind()
  deaths_since_save = deaths_since_save + 1
  if deaths_since_save >= config.deaths_per_checkpoint and #checkpoints > 1 then
    table.remove(checkpoints)
    deaths_since_save = 0
  end
  savestate.load(checkpoints[#checkpoints])
  pad:reset(frame)
  tracker:reset()
  saved_frame = frame
end

local was_dying, was_in_air, furthest_x, deaths = false, false, 0, 0

-- Plays one frame; returns false when the run is over.
local function play_frame()
  frame = frame + 1
  local snapshot = telemetry.read(memory.readbyte)
  local facts = telemetry.facts(snapshot)
  tracker:push(frame, snapshot.x)

  local dying = facts.screen == "playing" and facts.dying
  if facts.screen == "playing" and not dying then
    furthest_x = math.max(furthest_x, snapshot.x)
  end
  if dying and not was_dying then
    deaths = deaths + 1
    deaths_seen[#deaths_seen + 1] = { x = snapshot.x, cause = facts.death_cause }
    log({ type = "death", x = snapshot.x, cause = facts.death_cause, furthest_x = furthest_x, rewound = #checkpoints > 0 })
    if deaths >= config.max_deaths then
      return false
    end
    if #checkpoints > 0 then
      rewind()
      return true
    end
  end
  was_dying = dying
  if facts.screen == "playing" and facts.in_air and not was_in_air then
    log({ type = "takeoff", x = snapshot.x, speed = snapshot.x_speed, jumped = facts.jumped })
  end
  local landed = was_in_air and not facts.in_air
  was_in_air = facts.in_air
  if facts.level_complete then
    log({ type = "level_complete" })
    return false
  end
  if facts.screen == "game_over" then
    log({ type = "game_over" })
    return false
  end
  save_checkpoint(facts)

  if policy == "jev" then
    if frame % config.call_every_frames == 0 then
      post_job(facts, snapshot.x)
    end
    apply_answers(facts)
    rearm_jump(facts, landed)
    retap_start()
  else
    baseline(facts)
  end
  local keys = joypad_for(facts)
  if policy == "jev" then
    overlay.draw(gui, { result = applied_result, keys = keys, press_at = config.controller.press_at })
  end
  joypad.set(1, keys)
  emu.frameadvance()
  return true
end

local ticks = assert(io.open(exchange_dir .. "/ticks", "rb"))
emu.speedmode("nothrottle")
log({ type = "start", policy = policy, rewinds = rewinds })
while ticks:read(1) and play_frame() do
end

log({ type = "end", jobs_posted = seq, furthest_x = furthest_x, deaths = deaths })
events:close()
box:request_stop()
