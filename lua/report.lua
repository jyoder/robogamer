-- Summarizes a run directory: call results, answer freshness and how far Mario got on each life.
local json = require("vendor.dkjson")

local report = {}

-- Level x where Mario is clear of World 1-1's first Goomba, just before the first pipe.
report.FIRST_GOOMBA_CLEARED_X = 430

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
  local summary = { lives = {}, errors = {}, calls = 0, failed = 0, applied = 0 }
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
    elseif event.type == "death" or event.type == "level_complete" or event.type == "end" then
      if event.max_x > 0 then
        summary.lives[#summary.lives + 1] = { max_x = event.max_x, ended_by = event.type }
      end
      summary.jobs_posted = event.jobs_posted or summary.jobs_posted
    elseif event.type == "start" then
      summary.policy = event.policy
    end
  end
  summary.latency_ms = { median = percentile(latencies, 0.5), p90 = percentile(latencies, 0.9) }
  summary.age_frames = { median = percentile(ages, 0.5), p90 = percentile(ages, 0.9) }
  summary.cleared_first_goomba = 0
  for _, life in ipairs(summary.lives) do
    if life.max_x >= report.FIRST_GOOMBA_CLEARED_X then
      summary.cleared_first_goomba = summary.cleared_first_goomba + 1
    end
  end
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
  for i, life in ipairs(s.lives) do
    print(string.format("  life %d: reached x=%d (%s)", i, life.max_x, life.ended_by))
  end
  print(string.format("  lives clearing the first Goomba: %d of %d", s.cleared_first_goomba, #s.lives))
end

if arg and arg[0] and arg[0]:match("report%.lua$") then
  report.print(arg[1] or io.popen("ls -dt runs/*/ | head -1"):read("*l"):gsub("/$", ""))
end

return report
