-- File-based exchange between the emulator script and the workers.
-- The emulator posts one job at a time into a single mailbox file; posting replaces any job no
-- worker has claimed yet, so stale work never queues up. A worker claims the job by renaming the
-- file to a name only it uses, which succeeds for exactly one worker. Results are written per job
-- sequence number, each by one worker, and double as the run's call log.
local json = require("vendor.dkjson")

local mailbox = {}

local Mailbox = {}
Mailbox.__index = Mailbox

local function write_atomic(path, data)
  local tmp = path .. ".tmp"
  local f = assert(io.open(tmp, "wb"))
  f:write(data)
  f:close()
  assert(os.rename(tmp, path))
end

local function read_file(path)
  local f = io.open(path, "rb")
  if not f then
    return nil
  end
  local data = f:read("*a")
  f:close()
  return data
end

-- dir holds the job mailbox, frames and the stop flag; results_dir holds one file per job.
function mailbox.open(dir, results_dir)
  return setmetatable({
    dir = dir,
    results_dir = results_dir,
    job_path = dir .. "/job.json",
    stop_path = dir .. "/stop",
  }, Mailbox)
end

-- Clears what a previous run left behind so a new run starts from the same state.
function Mailbox:reset()
  assert(os.execute(string.format("rm -rf '%s' && mkdir -p '%s/frames' '%s'", self.dir, self.dir, self.results_dir)) == 0)
end

function Mailbox:frame_path(frame)
  return string.format("%s/frames/%d.gd", self.dir, frame)
end

function Mailbox:write_frame(frame, data)
  write_atomic(self:frame_path(frame), data)
end

function Mailbox:remove_frame(frame)
  os.remove(self:frame_path(frame))
end

function Mailbox:post_job(job)
  write_atomic(self.job_path, json.encode(job))
end

-- Returns the job if this worker won it, or nil when there is no job or another worker took it.
function Mailbox:claim_job(worker_id)
  local claimed = string.format("%s/claimed-%s.json", self.dir, worker_id)
  if not os.rename(self.job_path, claimed) then
    return nil
  end
  local job = json.decode(read_file(claimed))
  os.remove(claimed)
  return job
end

function Mailbox:result_path(seq)
  return string.format("%s/%d.json", self.results_dir, seq)
end

function Mailbox:post_result(seq, result)
  write_atomic(self:result_path(seq), json.encode(result))
end

function Mailbox:read_result(seq)
  local data = read_file(self:result_path(seq))
  return data and json.decode(data)
end

function Mailbox:request_stop()
  write_atomic(self.stop_path, "")
end

function Mailbox:stop_requested()
  return read_file(self.stop_path) ~= nil
end

return mailbox
