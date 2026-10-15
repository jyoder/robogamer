-- Scores the current prompt against labeled moments from recorded runs.
-- Usage: luajit lua/score.lua [run_dir ...]  (defaults to every run that kept its frames)
local root = io.popen("cd \"$(dirname '" .. arg[0] .. "')/..\" && pwd"):read("*l")
package.path = root .. "/lua/?.lua;" .. package.path

local cases = require("cases")
local config = require("config")
local jev_policy = require("jev_policy")
local typesafe = require("typesafe")
local worker = require("worker")

-- Cases per label, taken evenly across runs so one long run does not dominate.
local MAX_PER_LABEL = 60

local function runs_with_frames()
  local runs = {}
  for dir in io.popen("ls -d '" .. root .. "/" .. config.runs_dir .. "/'*/frames 2>/dev/null"):lines() do
    runs[#runs + 1] = dir:gsub("/frames$", "")
  end
  return runs
end

local function evenly(list, n)
  if #list <= n then
    return list
  end
  local picked = {}
  for i = 1, n do
    picked[i] = list[math.floor((i - 1) * #list / n) + 1]
  end
  return picked
end

local function read_png(run_dir, frame)
  local f = assert(io.open(worker.png_path(run_dir .. "/frames", frame), "rb"))
  local data = f:read("*a")
  f:close()
  return data
end

local runs = #arg > 0 and arg or runs_with_frames()
local by_label = { jump = {}, walk = {} }
for _, run_dir in ipairs(runs) do
  for _, case in ipairs(cases.collect(run_dir)) do
    table.insert(by_label[case.label], case)
  end
end

local client = typesafe.client({ model = config.model })
local press_at = config.controller.press_at
local tally = {}

local function count(key, a, played_a, pressed_is_right)
  local t = tally[key] or { n = 0, a = 0, played_a = 0, right = 0 }
  tally[key] = t
  t.n = t.n + 1
  t.a = t.a + a
  t.played_a = t.played_a + played_a
  if (a > press_at) == pressed_is_right then
    t.right = t.right + 1
  end
end

local failures = 0
for kind, list in pairs(by_label) do
  for _, case in ipairs(evenly(list, MAX_PER_LABEL)) do
    local request = jev_policy.build(worker.observation(case.job, function(frame) return read_png(case.run_dir, frame) end))
    local response, err = client:systemone(request)
    if response then
      local a = jev_policy.decode(response.answers).a
      count(kind, a, case.played_a, kind == "jump")
    else
      failures = failures + 1
      io.stderr:write(err, "\n")
    end
  end
end

print(string.format("%d runs; A is pressed above %.2f", #runs, press_at))
local keys = {}
for key in pairs(tally) do
  keys[#keys + 1] = key
end
table.sort(keys)
for _, key in ipairs(keys) do
  local t = tally[key]
  print(string.format("  %-14s n=%3d  mean A %.2f (when played %.2f)  correct %d%%",
    key, t.n, t.a / t.n, t.played_a / t.n, math.floor(100 * t.right / t.n + 0.5)))
end
if tally.jump and tally.walk then
  print(string.format("  balanced accuracy %d%%",
    math.floor(50 * (tally.jump.right / tally.jump.n + tally.walk.right / tally.walk.n) + 0.5)))
end
if failures > 0 then
  print(string.format("  %d calls failed", failures))
end
