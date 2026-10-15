-- Summarizes a run directory: call results, answer freshness, how far Mario got and where he died.
local run_log = require("run_log")

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

function report.summarize(run_dir)
  local summary = { deaths_at = {}, deaths = 0, furthest_x = 0, errors = {}, calls = 0, failed = 0, applied = 0 }
  local latencies, ages = {}, {}
  for _, result in ipairs(run_log.results(run_dir)) do
    summary.calls = summary.calls + 1
    if result.error then
      summary.failed = summary.failed + 1
      summary.errors[result.error] = (summary.errors[result.error] or 0) + 1
    else
      latencies[#latencies + 1] = result.latency_ms
    end
  end
  for _, event in ipairs(run_log.events(run_dir)) do
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
      summary.frames = event.frame
    elseif event.type == "start" then
      summary.policy = event.policy
      summary.rewinds = event.rewinds
    end
  end
  summary.latency_ms = { median = percentile(latencies, 0.5), p90 = percentile(latencies, 0.9) }
  summary.age_frames = { median = percentile(ages, 0.5), p90 = percentile(ages, 0.9) }
  return summary
end

-- summaries: array of report.summarize results. Returns runs, completed, medians of deaths,
-- furthest_x and frames, and deaths_at summed over all runs.
function report.combine(summaries)
  local combined = { runs = #summaries, completed = 0, deaths_at = {} }
  local lists = { deaths = {}, furthest_x = {}, frames = {} }
  for _, s in ipairs(summaries) do
    if s.level_complete then
      combined.completed = combined.completed + 1
    end
    for key, list in pairs(lists) do
      list[#list + 1] = s[key]
    end
    for spot, count in pairs(s.deaths_at) do
      combined.deaths_at[spot] = (combined.deaths_at[spot] or 0) + count
    end
  end
  for key, list in pairs(lists) do
    table.sort(list)
    combined[key] = { median = percentile(list, 0.5), min = list[1], max = list[#list] }
  end
  return combined
end

local function print_deaths_at(deaths_at)
  local spots = {}
  for spot in pairs(deaths_at) do
    spots[#spots + 1] = spot
  end
  table.sort(spots)
  for _, spot in ipairs(spots) do
    print(string.format("    x %d-%d: %d", spot, spot + DEATH_SPOT_WIDTH - 1, deaths_at[spot]))
  end
end

function report.print_combined(combined, fps)
  print(string.format("%d runs: level complete in %d (%d%%)", combined.runs, combined.completed,
    math.floor(100 * combined.completed / combined.runs + 0.5)))
  print(string.format("  deaths median %d (min %d, max %d)", combined.deaths.median, combined.deaths.min, combined.deaths.max))
  print(string.format("  furthest x median %d (min %d, max %d) of about %d", combined.furthest_x.median,
    combined.furthest_x.min, combined.furthest_x.max, report.LEVEL_END_X))
  print(string.format("  seconds played median %.0f", combined.frames.median / fps))
  print("  deaths by spot")
  print_deaths_at(combined.deaths_at)
end

function report.print(run_dir)
  local s = report.summarize(run_dir)
  print(string.format("run %s (%s%s)", run_dir, s.policy or "?", s.rewinds == false and ", lives only" or ""))
  print(string.format("  jobs posted %s, answered %d, failed %d, applied %d",
    tostring(s.jobs_posted), s.calls, s.failed, s.applied))
  for message, count in pairs(s.errors) do
    print(string.format("  error x%d: %s", count, message))
  end
  print(string.format("  latency ms median %s p90 %s", tostring(s.latency_ms.median), tostring(s.latency_ms.p90)))
  print(string.format("  answer age frames median %s p90 %s", tostring(s.age_frames.median), tostring(s.age_frames.p90)))
  print(string.format("  furthest x %d of about %d%s", s.furthest_x, report.LEVEL_END_X,
    s.level_complete and ", level complete" or ""))
  print(string.format("  deaths %d", s.deaths))
  print_deaths_at(s.deaths_at)
end

if arg and arg[0] and arg[0]:match("report%.lua$") then
  report.print(arg[1] or io.popen("ls -dt runs/*/ | head -1"):read("*l"):gsub("/$", ""))
end

return report
