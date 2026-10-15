-- Runs inside FCEUX (Lua 5.1, no ffi): plays one run in real time, one frame per launcher tick.
local lua_dir = debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")
package.path = lua_dir .. "/?.lua;" .. package.path

local config = require("config")
local mailbox = require("mailbox")
local controller = require("controller")
local telemetry = require("telemetry")
local json = require("vendor.dkjson")

local run_dir = assert(os.getenv("ROBOGAMER_RUN_DIR"), "start runs with `mise run play`")
local exchange_dir = assert(os.getenv("ROBOGAMER_EXCHANGE_DIR"))
local policy = assert(os.getenv("ROBOGAMER_POLICY"))

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
local shots = {}
local posted_frame = {}
local seq, applied_seq, applied_frame = 0, 0, 0

local function post_job(facts)
  box:write_frame(frame, gui.gdscreenshot())
  shots[#shots + 1] = frame
  while shots[1] < frame - oldest_frame_ago - config.max_staleness_frames do
    box:remove_frame(table.remove(shots, 1))
  end

  local frames = {}
  for _, ago in ipairs(config.frames_ago) do
    if frame - ago >= shots[1] then
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
        applied_frame = frame
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

-- Mario only jumps on a fresh press of A, so A still held after he lands is released.
local function rearm_jump(facts)
  if not facts.in_air and pad:held_frames("a", frame) > config.grounded_a_frames then
    pad:release("a", frame)
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

local ticks = assert(io.open(exchange_dir .. "/ticks", "rb"))
emu.speedmode("nothrottle")
log({ type = "start", policy = policy })

local was_dying, life_max_x = false, 0
while ticks:read(1) do
  frame = frame + 1
  local snapshot = telemetry.read(memory.readbyte)
  local facts = telemetry.facts(snapshot)
  tracker:push(frame, snapshot.x)

  local dying = facts.screen == "playing" and facts.dying
  if facts.screen == "playing" and not dying then
    life_max_x = math.max(life_max_x, snapshot.x)
  end
  if dying and not was_dying then
    log({ type = "death", x = snapshot.x, max_x = life_max_x, lives = snapshot.lives })
    life_max_x = 0
  end
  was_dying = dying
  if facts.level_complete then
    log({ type = "level_complete", max_x = life_max_x })
    break
  end
  if facts.screen == "game_over" then
    log({ type = "game_over" })
    break
  end

  if policy == "jev" then
    if frame % config.call_every_frames == 0 then
      post_job(facts)
    end
    apply_answers(facts)
    rearm_jump(facts)
  else
    baseline(facts)
  end
  joypad.set(1, joypad_for(facts))
  emu.frameadvance()
end

log({ type = "end", jobs_posted = seq, max_x = life_max_x })
events:close()
box:request_stop()
