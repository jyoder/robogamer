local cases = require("cases")
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
  assert(os.execute("mkdir -p '" .. dir .. "/results' '" .. dir .. "/frames'") == 0)
  write(dir .. "/events.jsonl", json.encode({ type = "death", frame = 200, x = 300, cause = "enemy" }) .. "\n" ..
    json.encode({ type = "death", frame = 1000, x = 1140, cause = "pit" }) .. "\n")
  local moments = {
    { frame = 150, a = 0.3 },
    { frame = 960, a = 0.3 },
    { frame = 100, a = 0.3 },
    { frame = 400, a = 0.2 },
    { frame = 404, a = 0.9 },
    { frame = 420, a = 0.2, in_air = true },
    { frame = 430, a = 0.2, missing_png = true },
    { frame = 600, a = 0.4, stuck = true },
  }
  for seq, moment in ipairs(moments) do
    if not moment.missing_png then
      write(string.format("%s/frames/%d.png", dir, moment.frame), "png")
    end
    write(string.format("%s/results/%d.json", dir, seq), json.encode({
      seq = seq,
      frame = moment.frame,
      controls = { dpad = "right", a = moment.a, b = 0, start = 0, select = 0 },
      job = { frame = moment.frame, frames = { { frame = moment.frame, seconds_ago = 0 } },
        screen = "playing", in_air = moment.in_air or false, stuck = moment.stuck or false },
    }))
  end
  return dir
end

return {
  { "labels ground moments by what happened next", function()
    local found = cases.collect(fixture_run())
    local labels = {}
    for _, case in ipairs(found) do
      labels[case.job.frame] = case.label
    end
    check.eq(labels[150], "jump", "on the ground just before an enemy hit")
    check.eq(labels[960], nil, "before a fall into a pit is ambiguous")
    check.eq(labels[100], nil, "a death soon but outside the jump window is ambiguous")
    check.eq(labels[400], "walk", "not jumping and survived")
    check.eq(labels[404], nil, "jumping with no death after says nothing")
    check.eq(labels[420], nil, "in the air")
    check.eq(labels[430], nil, "frames not kept")
    check.eq(labels[600], "stuck", "blocked on the ground")
    check.eq(#found, 3, "case count")
  end },
  { "a case carries the controls played at the time", function()
    for _, case in ipairs(cases.collect(fixture_run())) do
      if case.label == "jump" then
        check.eq(case.played.a, 0.3, "played A")
      end
    end
  end },
}
