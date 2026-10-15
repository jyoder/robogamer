local report = require("report")
local check = require("check")
local json = require("vendor.dkjson")

local function write(path, text)
  local f = assert(io.open(path, "w"))
  f:write(text)
  f:close()
end

local function fixture_run()
  local dir = os.tmpname()
  os.remove(dir)
  assert(os.execute("mkdir -p '" .. dir .. "/results'") == 0)
  local results = {
    { seq = 1, latency_ms = 150, controls = {} },
    { seq = 2, latency_ms = 170, controls = {} },
    { seq = 3, error = "HTTP 500: boom" },
    { seq = 4, latency_ms = 400, controls = {} },
  }
  for _, result in ipairs(results) do
    write(string.format("%s/results/%d.json", dir, result.seq), json.encode(result))
  end
  local events = {
    { type = "start", policy = "jev" },
    { type = "applied", age = 9 },
    { type = "applied", age = 11 },
    { type = "applied", age = 14 },
    { type = "death", x = 297, furthest_x = 297 },
    { type = "death", x = 1139, furthest_x = 1139 },
    { type = "death", x = 1140, furthest_x = 1150 },
    { type = "level_complete" },
    { type = "end", jobs_posted = 40, furthest_x = 3168 },
  }
  local lines = {}
  for i, event in ipairs(events) do
    lines[i] = json.encode(event)
  end
  write(dir .. "/events.jsonl", table.concat(lines, "\n") .. "\n")
  return dir
end

return {
  { "counts calls, failures and their messages", function()
    local s = report.summarize(fixture_run())
    check.eq(s.calls, 4, "calls")
    check.eq(s.failed, 1, "failed")
    check.eq(s.errors["HTTP 500: boom"], 1, "error count")
    check.eq(s.jobs_posted, 40, "jobs posted")
    check.eq(s.policy, "jev", "policy")
  end },
  { "reports latency of successful calls and answer age", function()
    local s = report.summarize(fixture_run())
    check.eq(s.latency_ms.median, 170, "latency median")
    check.eq(s.latency_ms.p90, 400, "latency p90")
    check.eq(s.applied, 3, "applied")
    check.eq(s.age_frames.median, 11, "age median")
  end },
  { "groups deaths by spot and reports the furthest x and level completion", function()
    local s = report.summarize(fixture_run())
    check.eq(s.deaths, 3, "deaths")
    check.eq(s.deaths_at[288], 1, "deaths near the first Goomba")
    check.eq(s.deaths_at[1120], 2, "deaths at the first pit")
    check.eq(s.furthest_x, 3168, "furthest x")
    check.eq(s.level_complete, true, "level complete")
  end },
}
