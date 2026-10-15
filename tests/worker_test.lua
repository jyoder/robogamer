local image = require("image")
local png = require("png")
local mailbox = require("mailbox")
local typesafe = require("typesafe")
local clock = require("clock")
local worker = require("worker")
local check = require("check")

local WIDTH, HEIGHT = 256, 240

local function fresh_box()
  local base = os.tmpname()
  os.remove(base)
  local box = mailbox.open(base .. "/exchange", base .. "/results")
  box:reset()
  return box
end

local function solid_gd(r, g, b)
  local header = string.char(0xff, 0xfe, 1, 0, 0, 240, 1, 0xff, 0xff, 0xff, 0xff)
  return header .. string.rep(string.char(0, r, g, b), WIDTH * HEIGHT)
end

local function solid_png_base64(r, g, b)
  local img = image.new(WIDTH * 2, HEIGHT * 2)
  for y = 0, img.height - 1 do
    for x = 0, img.width - 1 do
      image.set(img, x, y, r, g, b)
    end
  end
  return typesafe.png_asset(png.encode(img)).data_base64
end

local COLORS = { [40] = { 255, 0, 0 }, [44] = { 0, 0, 255 }, [48] = { 0, 255, 0 } }

local function write_frames(box)
  for frame, rgb in pairs(COLORS) do
    box:write_frame(frame, solid_gd(rgb[1], rgb[2], rgb[3]))
  end
end

local function job(seq, older, newer)
  return {
    seq = seq,
    frame = newer,
    frames = { { frame = older, seconds_ago = 0.2 }, { frame = newer, seconds_ago = 0 } },
    controller_now = { dpad = "right, held 1.2 s", a = "released" },
    controller_history = { "1.2 s ago: right pressed" },
    progress_recently = "moved_right",
    stuck = false,
    in_air = true,
    screen = "playing",
  }
end

local ANSWERS = {
  dpad = { type = "choice", choice = "right", confidence = 0.8 },
  a = { type = "noul", noul = 0.7 },
  b = { type = "noul", noul = 0.6 },
  start = { type = "noul", noul = 0.1 },
  select = { type = "noul", noul = 0.0 },
  enemy_close_ahead = { type = "noul", noul = 0.2 },
  gap_ahead = { type = "noul", noul = 0.9 },
  obstacle_ahead = { type = "noul", noul = 0.3 },
  mario_visible = { type = "noul", noul = 1.0 },
  mario_in_air = { type = "noul", noul = 0.4 },
}

local function fake_client(response, err)
  local client = { requests = {} }
  function client:systemone(request)
    self.requests[#self.requests + 1] = request
    return response, err
  end
  return client
end

local function check_error(err, expected, label)
  assert(err and err:find(expected, 1, true), label .. ": unexpected error " .. tostring(err))
end

return {
  { "a job posts the decoded controls and diagnostics", function()
    local box = fresh_box()
    write_frames(box)
    local client = fake_client({ answers = ANSWERS })
    worker.new({ id = "w1", box = box, client = client }):handle(job(3, 40, 44))

    local result = box:read_result(3)
    check.eq(result.seq, 3, "seq")
    check.eq(result.frame, 44, "frame")
    check.eq(result.worker, "w1", "worker")
    check.eq(result.error, nil, "error")
    check.eq(result.controls.dpad, "right", "dpad")
    check.eq(result.controls.a, 0.7, "a")
    check.eq(result.controls.select, 0, "select")
    check.eq(result.diagnostics.gap_ahead, 0.9, "gap_ahead")
    check.eq(result.diagnostics.mario_visible, 1, "mario_visible")
    check.eq(type(result.latency_ms), "number", "latency_ms")
    check.eq(type(result.encode_ms), "number", "encode_ms")
  end },
  { "the request carries the job's frames as upscaled PNGs and its state", function()
    local box = fresh_box()
    write_frames(box)
    local client = fake_client({ answers = ANSWERS })
    worker.new({ id = "w1", box = box, client = client }):handle(job(3, 40, 44))

    check.eq(#client.requests, 1, "requests")
    local request = client.requests[1]
    local asset_count = 0
    for _ in pairs(request.assets) do
      asset_count = asset_count + 1
    end
    check.eq(asset_count, 2, "image assets")
    local frames = request.state.frames
    check.eq(frames[1].taken, "0.20 seconds ago", "older frame label")
    check.eq(frames[2].taken, "now", "newer frame label")
    check.eq(request.assets[frames[1].image].data_base64, solid_png_base64(255, 0, 0), "older frame is frame 40 at 512x480")
    check.eq(request.assets[frames[2].image].data_base64, solid_png_base64(0, 0, 255), "newer frame is frame 44 at 512x480")
    check.eq(request.state.controller_now.dpad, "right, held 1.2 s", "controller_now")
    check.eq(request.state.controller_history[1], "1.2 s ago: right pressed", "controller_history")
    check.eq(request.state.progress_recently, "moved_right", "progress_recently")
    check.eq(request.state.stuck, false, "stuck")
    check.eq(request.state.in_air, true, "in_air")
    check.eq(request.state.screen, "playing", "screen")
  end },
  { "an API error is posted as the result's error", function()
    local box = fresh_box()
    write_frames(box)
    local w = worker.new({ id = "w1", box = box, client = fake_client(nil, "HTTP 500: boom") })
    w:handle(job(4, 40, 44))

    local result = box:read_result(4)
    check.eq(result.error, "HTTP 500: boom", "error")
    check.eq(result.controls, nil, "controls")
    check.eq(type(result.latency_ms), "number", "latency_ms")
  end },
  { "a malformed answer is posted as the result's error", function()
    local box = fresh_box()
    write_frames(box)
    local w = worker.new({ id = "w1", box = box, client = fake_client({ answers = { a = { noul = 0.5 } } }) })
    w:handle(job(5, 40, 44))

    local result = box:read_result(5)
    check.eq(result.controls, nil, "controls")
    check_error(result.error, "attempt to index", "malformed answer")
  end },
  { "a missing frame file is posted as the result's error without calling the API", function()
    local box = fresh_box()
    write_frames(box)
    local client = fake_client({ answers = ANSWERS })
    worker.new({ id = "w1", box = box, client = client }):handle(job(6, 40, 99))

    local result = box:read_result(6)
    check.eq(result.controls, nil, "controls")
    check_error(result.error, "frame 99 is missing", "missing frame")
    check.eq(#client.requests, 0, "requests")
  end },
  { "frames shared with the previous job are not read again", function()
    local box = fresh_box()
    write_frames(box)
    local reads = {}
    local w = worker.new({
      id = "w1",
      box = box,
      client = fake_client({ answers = ANSWERS }),
      read_frame = function(path)
        reads[#reads + 1] = path:match("(%d+)%.gd$")
        local f = assert(io.open(path, "rb"))
        local data = f:read("*a")
        f:close()
        return data
      end,
    })
    w:handle(job(1, 40, 44))
    w:handle(job(2, 44, 48))
    w:handle(job(3, 40, 48))
    check.eq(table.concat(reads, ","), "40,44,48,40", "frames read")
  end },
  { "run handles posted jobs and exits once stop is requested", function()
    local box = fresh_box()
    write_frames(box)
    local client = fake_client({ answers = ANSWERS })
    function client:systemone()
      box:request_stop()
      return { answers = ANSWERS }
    end
    box:post_job(job(7, 40, 44))
    worker.new({ id = "w1", box = box, client = client, idle_seconds = 5 }):run()

    check.eq(box:read_result(7).controls.dpad, "right", "handled job")
  end },
  { "run exits after idle_seconds without a job", function()
    local box = fresh_box()
    local started = clock.now()
    worker.new({ id = "w1", box = box, client = fake_client(), idle_seconds = 0.05 }):run()
    local elapsed = clock.now() - started
    assert(elapsed >= 0.05 and elapsed < 1, "idle exit took " .. elapsed .. " s")
  end },
}
