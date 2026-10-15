-- Runs every test suite: luajit tests/run.lua. Set LIVE=1 to include calls to the TypeSafe API.
local root = arg[0]:match("^(.*)/tests/[^/]+$") or "."
package.path = root .. "/lua/?.lua;" .. root .. "/tests/?.lua;" .. package.path

local suites = { "image_test", "png_test", "typesafe_test", "jev_policy_test" }
if os.getenv("LIVE") == "1" then
  suites[#suites + 1] = "live_test"
end

local passed, failed = 0, 0
for _, suite in ipairs(suites) do
  for _, test in ipairs(require(suite)) do
    local ok, err = xpcall(test[2], debug.traceback)
    if ok then
      passed = passed + 1
      print("ok    " .. suite .. ": " .. test[1])
    else
      failed = failed + 1
      print("FAIL  " .. suite .. ": " .. test[1] .. "\n" .. err)
    end
  end
end

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
