-- Plays several runs on Mario's lives alone (no rewinds) and summarizes them together.
-- Usage: luajit lua/bench.lua [runs] [jev|baseline]
local root = io.popen("cd \"$(dirname '" .. arg[0] .. "')/..\" && pwd"):read("*l")
package.path = root .. "/lua/?.lua;" .. package.path

local config = require("config")
local report = require("report")

local runs = tonumber(arg[1]) or 5
local policy = arg[2] or "jev"

io.stdout:setvbuf("line")
local summaries = {}
for i = 1, runs do
  print(string.format("== bench run %d of %d", i, runs))
  local play = io.popen(string.format("luajit '%s/lua/play.lua' %s --lives 2>&1", root, policy))
  for line in play:lines() do
    print(line)
    local run_dir = line:match("^run (%S+)$")
    if run_dir then
      summaries[#summaries + 1] = run_dir
    end
  end
  play:close()
end

for i, run_dir in ipairs(summaries) do
  summaries[i] = report.summarize(run_dir)
end
print()
report.print_combined(report.combine(summaries), config.fps)
