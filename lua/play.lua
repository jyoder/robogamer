-- Starts a run: the workers, FCEUX running lua/main.lua, and the metronome that paces it.
-- FCEUX's own speed throttle never advances a frame on this macOS build, so the emulator runs
-- unthrottled and waits for one byte from the metronome before each frame.
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

local policy = arg[1] or "jev"
assert(policy == "jev" or policy == "baseline", "policy must be jev or baseline")

local exchange_dir = root .. "/" .. config.exchange_dir
local run_dir = string.format("%s/%s/%s-%s", root, config.runs_dir, os.date("%Y%m%d-%H%M%S"), policy)
local box = mailbox.open(exchange_dir, run_dir .. "/results")
box:reset()
local ticks_path = exchange_dir .. "/ticks"
assert(os.execute(string.format("mkfifo '%s'", ticks_path)) == 0)

if policy == "jev" then
  for i = 1, config.workers do
    assert(os.execute(string.format("luajit '%s/lua/worker.lua' w%d '%s' '%s' 2>>'%s/workers.log' &",
      root, i, exchange_dir, box.results_dir, run_dir)) == 0)
  end
end

assert(os.execute(string.format(
  "ROBOGAMER_RUN_DIR='%s' ROBOGAMER_EXCHANGE_DIR='%s' ROBOGAMER_POLICY=%s " ..
  "fceux --sound 0 --loadlua '%s/lua/main.lua' '%s/roms/smb.nes' >'%s/fceux.log' 2>&1 &",
  run_dir, exchange_dir, policy, root, root, run_dir)) == 0)

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
