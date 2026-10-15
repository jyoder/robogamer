local clock = require("clock")
local check = require("check")

return {
  { "sleep waits about as long as asked", function()
    local start = clock.now()
    clock.sleep(0.05)
    local elapsed = clock.now() - start
    check.eq(elapsed >= 0.05 and elapsed < 0.2, true, string.format("elapsed %.3f s", elapsed))
  end },
  { "non-positive sleeps return at once", function()
    local start = clock.now()
    clock.sleep(0)
    clock.sleep(-1)
    check.eq(clock.now() - start < 0.01, true, "elapsed")
  end },
}
