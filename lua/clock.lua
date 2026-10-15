-- Monotonic wall-clock time and sleeping for LuaJIT processes.
local ffi = require("ffi")

ffi.cdef [[
  struct robogamer_timespec { long tv_sec; long tv_nsec; };
  int clock_gettime(int clock_id, struct robogamer_timespec *ts);
  int nanosleep(const struct robogamer_timespec *req, struct robogamer_timespec *rem);
]]

local CLOCK_MONOTONIC = ffi.os == "OSX" and 6 or 1

local clock = {}

local now_ts = ffi.new("struct robogamer_timespec")
local sleep_ts = ffi.new("struct robogamer_timespec")

function clock.now()
  ffi.C.clock_gettime(CLOCK_MONOTONIC, now_ts)
  return tonumber(now_ts.tv_sec) + tonumber(now_ts.tv_nsec) * 1e-9
end

function clock.sleep(seconds)
  if seconds <= 0 then
    return
  end
  local whole = math.floor(seconds)
  sleep_ts.tv_sec = whole
  sleep_ts.tv_nsec = (seconds - whole) * 1e9
  ffi.C.nanosleep(sleep_ts, nil)
end

return clock
