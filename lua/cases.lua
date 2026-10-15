-- Labels moments from recorded runs, judged by what happened next, for scoring the A question offline.
local config = require("config")
local run_log = require("run_log")
local worker = require("worker")

local cases = {}

-- Mario on the ground this close before an enemy hit should have been jumping. Before a fall into
-- a pit he usually did jump, too early or too slowly, so those moments get no label.
cases.JUMP_WINDOW_FRAMES = 60
-- Mario on the ground, not jumping, who survives this long was fine to keep walking.
cases.SAFE_FRAMES = 120

local function frames_kept(run_dir, job)
  for _, frame in ipairs(job.frames) do
    local f = io.open(worker.png_path(run_dir .. "/frames", frame.frame), "rb")
    if not f then
      return false
    end
    f:close()
  end
  return true
end

-- Returns "jump", "stuck" (blocked on the ground, so he should jump), "walk", or nil when the
-- moment is ambiguous.
local function label(job, a, deaths)
  if job.stuck then
    return "stuck"
  end
  local frame = job.frame
  for _, death in ipairs(deaths) do
    if death.frame >= frame and death.frame - frame <= cases.SAFE_FRAMES then
      if death.cause == "enemy" and death.frame - frame <= cases.JUMP_WINDOW_FRAMES then
        return "jump"
      end
      return nil
    end
  end
  if a < config.controller.press_at then
    return "walk"
  end
end

-- Returns { label, run_dir, job, played } for each labeled moment in the run; played is the
-- controls Jev answered at the time.
function cases.collect(run_dir)
  local deaths = {}
  for _, event in ipairs(run_log.events(run_dir)) do
    if event.type == "death" then
      deaths[#deaths + 1] = event
    end
  end
  local found = {}
  for _, result in ipairs(run_log.results(run_dir)) do
    local job = result.job
    if job and result.controls and job.screen == "playing" and not job.in_air and frames_kept(run_dir, job) then
      local kind = label(job, result.controls.a, deaths)
      if kind then
        found[#found + 1] = { label = kind, run_dir = run_dir, job = job, played = result.controls }
      end
    end
  end
  return found
end

return cases
