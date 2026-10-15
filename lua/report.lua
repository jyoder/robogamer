-- Summarizes a run directory: call results, answer freshness, how far Mario got and where he died.
local json = require("vendor.dkjson")

local report = {}

-- Level x of World 1-1's flagpole.
report.LEVEL_END_X = 3168

-- Deaths are grouped into spots two blocks wide.
local DEATH_SPOT_WIDTH = 32

local function percentile(values, p)
  if #values == 0 then
    return nil
  end
  table.sort(values)
  return values[math.max(1, math.ceil(#values * p))]
end

local function read_lines(path)
  local lines = {}
  local f = io.open(path)
  if f then
    for line in f:lines() do
      lines[#lines + 1] = line
    end
    f:close()
  end
  return lines
end

local function read_results(dir)
  local results = {}
  local listing = io.popen("ls '" .. dir .. "' 2>/dev/null")
  for name in listing:lines() do
    if name:match("^%d+%.json$") then
      local f = io.open(dir .. "/" .. name)
      results[#results + 1] = json.decode(f:read("*a"))
      f:close()
    end
  end
  listing:close()
  return results
end

function report.summarize(run_dir)
  local summary = { deaths_at = {}, deaths = 0, furthest_x = 0, errors = {}, calls = 0, failed = 0, applied = 0 }
  local latencies, ages = {}, {}
  for _, result in ipairs(read_results(run_dir .. "/results")) do
    summary.calls = summary.calls + 1
    if result.error then
      summary.failed = summary.failed + 1
      summary.errors[result.error] = (summary.errors[result.error] or 0) + 1
    else
      latencies[#latencies + 1] = result.latency_ms
    end
  end
  for _, line in ipairs(read_lines(run_dir .. "/events.jsonl")) do
    local event = json.decode(line)
    if event.type == "applied" then
      summary.applied = summary.applied + 1
      ages[#ages + 1] = event.age
    elseif event.type == "death" then
      summary.deaths = summary.deaths + 1
      local spot = math.floor(event.x / DEATH_SPOT_WIDTH) * DEATH_SPOT_WIDTH
      summary.deaths_at[spot] = (summary.deaths_at[spot] or 0) + 1
      summary.furthest_x = math.max(summary.furthest_x, event.furthest_x)
    elseif event.type == "level_complete" then
      summary.level_complete = true
    elseif event.type == "end" then
      summary.jobs_posted = event.jobs_posted
      summary.furthest_x = math.max(summary.furthest_x, event.furthest_x)
    elseif event.type == "start" then
      summary.policy = event.policy
    end
  end
  summary.latency_ms = { median = percentile(latencies, 0.5), p90 = percentile(latencies, 0.9) }
  summary.age_frames = { median = percentile(ages, 0.5), p90 = percentile(ages, 0.9) }
  return summary
end

function report.print(run_dir)
  local s = report.summarize(run_dir)
  print(string.format("run %s (%s)", run_dir, s.policy or "?"))
  print(string.format("  jobs posted %s, answered %d, failed %d, applied %d",
    tostring(s.jobs_posted), s.calls, s.failed, s.applied))
  for message, count in pairs(s.errors) do
    print(string.format("  error x%d: %s", count, message))
  end
  print(string.format("  latency ms median %s p90 %s", tostring(s.latency_ms.median), tostring(s.latency_ms.p90)))
  print(string.format("  answer age frames median %s p90 %s", tostring(s.age_frames.median), tostring(s.age_frames.p90)))
  print(string.format("  furthest x %d of about %d%s", s.furthest_x, report.LEVEL_END_X,
    s.level_complete and ", level complete" or ""))
  local spots = {}
  for spot in pairs(s.deaths_at) do
    spots[#spots + 1] = spot
  end
  table.sort(spots)
  print(string.format("  deaths %d", s.deaths))
  for _, spot in ipairs(spots) do
    print(string.format("    x %d-%d: %d", spot, spot + DEATH_SPOT_WIDTH - 1, s.deaths_at[spot]))
  end
end

if arg and arg[0] and arg[0]:match("report%.lua$") then
  report.print(arg[1] or io.popen("ls -dt runs/*/ | head -1"):read("*l"):gsub("/$", ""))
end

return report
