-- Starts a run: the workers, FCEUX running lua/main.lua, and the metronome that paces it.
-- FCEUX's own speed throttle never advances a frame on macOS, so the emulator runs unthrottled
-- and waits for one byte from the metronome before each frame. The patched build in build/fceux
-- keeps sound at normal speed while unthrottled; stock FCEUX garbles it.
local root = io.popen("cd \"$(dirname '" .. arg[0] .. "')/..\" && pwd"):read("*l")
package.path = root .. "/lua/?.lua;" .. package.path

local ffi = require("ffi")
local clock = require("clock")
local config = require("config")
local mailbox = require("mailbox")
local report = require("report")

ffi.cdef [[
  typedef void (*robogamer_sighandler)(int);
  robogamer_sighandler signal(int sig, robogamer_sighandler handler);
]]
local SIGPIPE, SIG_IGN = 13, ffi.cast("robogamer_sighandler", 1)

-- Usage: luajit lua/play.lua [jev|baseline] [--lives]
-- --lives turns off rewinding to savestates, so Mario plays on his lives alone.
local policy, lives_only = "jev", false
for _, a in ipairs(arg) do
  if a == "--lives" then
    lives_only = true
  else
    policy = a
  end
end
assert(policy == "jev" or policy == "baseline", "policy must be jev or baseline")

local exchange_dir = root .. "/" .. config.exchange_dir
local run_dir = string.format("%s/%s/%s-%s", root, config.runs_dir, os.date("%Y%m%d-%H%M%S"), policy)
local box = mailbox.open(exchange_dir, run_dir .. "/results")
box:reset()
local ticks_path = exchange_dir .. "/ticks"
assert(os.execute(string.format("mkfifo '%s'", ticks_path)) == 0)

-- FCEUX reads $FCEUX_HOME/.fceux/fceux.cfg, so runs get their own settings instead of the user's.
-- The Qt build sizes its window from this file and ignores --xscale.
local fceux = root .. "/" .. config.fceux
assert(io.open(fceux, "rb"), fceux .. " is missing; run `mise run build:fceux`"):close()
local fceux_home = exchange_dir .. "/fceux"
assert(os.execute(string.format("mkdir -p '%s/.fceux'", fceux_home)) == 0)
local fceux_cfg = assert(io.open(fceux_home .. "/.fceux/fceux.cfg", "w"))
fceux_cfg:write(string.format(
  "SDL.WinSizeX = %d\nSDL.WinSizeY = %d\nSDL.XScale = %d\nSDL.YScale = %d\nSDL.Sound = %d\nSDL.Sound.Volume = %d\n",
  256 * config.window_scale, 240 * config.window_scale + 5, config.window_scale, config.window_scale,
  config.volume > 0 and 1 or 0, config.volume))
fceux_cfg:close()

if policy == "jev" then
  local frames_dir = run_dir .. "/frames"
  assert(os.execute(string.format("mkdir -p '%s'", frames_dir)) == 0)
  for i = 1, config.workers do
    assert(os.execute(string.format("luajit '%s/lua/worker.lua' w%d '%s' '%s' '%s' 2>>'%s/workers.log' &",
      root, i, exchange_dir, box.results_dir, frames_dir, run_dir)) == 0)
  end
end

assert(os.execute(string.format(
  "FCEUX_HOME='%s' ROBOGAMER_RUN_DIR='%s' ROBOGAMER_EXCHANGE_DIR='%s' ROBOGAMER_POLICY=%s ROBOGAMER_REWINDS=%d " ..
  "'%s' --loadlua '%s/lua/main.lua' '%s/roms/smb.nes' >'%s/fceux.log' 2>&1 &",
  fceux_home, run_dir, exchange_dir, policy, lives_only and 0 or 1, fceux, root, root, run_dir)) == 0)

io.stdout:setvbuf("line")
print("run " .. run_dir)
ffi.C.signal(SIGPIPE, SIG_IGN)
local ticks = assert(io.open(ticks_path, "wb"))
ticks:setvbuf("no")

local period = 1 / config.fps
local next_tick = clock.now()
local deadline = next_tick + config.max_run_seconds
while not box:stop_requested() and next_tick < deadline do
  if not ticks:write("t") then
    break
  end
  next_tick = next_tick + period
  clock.sleep(next_tick - clock.now())
end

box:request_stop()
ticks:close()
local fceux_pattern = string.format("'loadlua %s/lua/main.lua'", root)
os.execute("pkill -f " .. fceux_pattern .. "; sleep 1; pkill -9 -f " .. fceux_pattern)
report.print(run_dir)
