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
    { type = "death", max_x = 297 },
    { type = "death", max_x = 0 },
    { type = "level_complete", max_x = 3100 },
    { type = "end", jobs_posted = 40, max_x = 0 },
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
  { "lists lives that moved and counts those clearing the first Goomba", function()
    local s = report.summarize(fixture_run())
    check.eq(#s.lives, 2, "lives")
    check.eq(s.lives[1].max_x, 297, "first life")
    check.eq(s.lives[2].ended_by, "level_complete", "second life end")
    check.eq(s.cleared_first_goomba, 1, "cleared")
  end },
}
