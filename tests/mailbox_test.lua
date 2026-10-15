local mailbox = require("mailbox")
local check = require("check")

local function fresh()
  local base = os.tmpname()
  os.remove(base)
  local box = mailbox.open(base .. "/exchange", base .. "/results")
  box:reset()
  return box
end

return {
  { "a posted job is claimed once", function()
    local box = fresh()
    box:post_job({ seq = 1, frame = 40 })
    local job = box:claim_job("w1")
    check.eq(job.seq, 1, "claimed seq")
    check.eq(job.frame, 40, "claimed frame")
    check.eq(box:claim_job("w2"), nil, "second claim")
  end },
  { "claiming an empty mailbox returns nil", function()
    check.eq(fresh():claim_job("w1"), nil, "claim")
  end },
  { "posting replaces a job nobody claimed", function()
    local box = fresh()
    box:post_job({ seq = 1 })
    box:post_job({ seq = 2 })
    check.eq(box:claim_job("w1").seq, 2, "claimed seq")
    check.eq(box:claim_job("w1"), nil, "older job is gone")
  end },
  { "results round-trip by sequence number", function()
    local box = fresh()
    check.eq(box:read_result(7), nil, "missing result")
    box:post_result(7, { seq = 7, controls = { dpad = "right" } })
    check.eq(box:read_result(7).controls.dpad, "right", "result dpad")
  end },
  { "frames are written and removed by frame number", function()
    local box = fresh()
    box:write_frame(12, "pixels")
    local f = io.open(box:frame_path(12), "rb")
    check.eq(f:read("*a"), "pixels", "frame contents")
    f:close()
    box:remove_frame(12)
    check.eq(io.open(box:frame_path(12), "rb"), nil, "removed frame")
  end },
  { "stop is requested through a flag file and cleared by reset", function()
    local box = fresh()
    check.eq(box:stop_requested(), false, "before request")
    box:request_stop()
    check.eq(box:stop_requested(), true, "after request")
    box:reset()
    check.eq(box:stop_requested(), false, "after reset")
  end },
}
