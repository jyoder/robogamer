-- Reads what a run leaves in its directory: one result file per Jev call and events.jsonl.
local json = require("vendor.dkjson")

local run_log = {}

-- Returns the results in sequence order.
function run_log.results(run_dir)
  local results = {}
  local listing = io.popen("ls '" .. run_dir .. "/results' 2>/dev/null")
  for name in listing:lines() do
    if name:match("^%d+%.json$") then
      local f = io.open(run_dir .. "/results/" .. name)
      results[#results + 1] = json.decode(f:read("*a"))
      f:close()
    end
  end
  listing:close()
  table.sort(results, function(a, b) return a.seq < b.seq end)
  return results
end

function run_log.events(run_dir)
  local events = {}
  local f = io.open(run_dir .. "/events.jsonl")
  if f then
    for line in f:lines() do
      events[#events + 1] = json.decode(line)
    end
    f:close()
  end
  return events
end

return run_log
