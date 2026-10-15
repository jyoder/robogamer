-- A worker process: claims jobs from the mailbox, asks Jev for the controls, and posts the results.
-- Usage: luajit lua/worker.lua <worker_id> <exchange_dir> <results_dir>
local is_script = arg and arg[0] and arg[0]:match("worker%.lua$") ~= nil
if is_script then
  local lua_dir = arg[0]:match("^(.*)/[^/]+$") or "."
  package.path = lua_dir .. "/?.lua;" .. package.path
end

local capture = require("capture")
local clock = require("clock")
local config = require("config")
local image = require("image")
local jev_policy = require("jev_policy")
local mailbox = require("mailbox")
local png = require("png")
local typesafe = require("typesafe")

local worker = {}

local Worker = {}
Worker.__index = Worker

local function read_file(path)
  local f = io.open(path, "rb")
  if not f then
    return nil
  end
  local data = f:read("*a")
  f:close()
  return data
end

local function elapsed_ms(since)
  return (clock.now() - since) * 1000
end

-- opts: id, box (mailbox), client (anything with systemone(self, request)),
-- read_frame (path -> gd string or nil, defaults to reading the file), idle_seconds.
function worker.new(opts)
  return setmetatable({
    id = opts.id,
    box = opts.box,
    client = opts.client,
    read_frame = opts.read_frame or read_file,
    idle_seconds = opts.idle_seconds or config.worker_idle_seconds,
    pngs = {},
  }, Worker)
end

function Worker:png(frame)
  if not self.pngs[frame] then
    local path = self.box:frame_path(frame)
    local data = self.read_frame(path)
    if not data then
      error(string.format("frame %d is missing: %s", frame, path), 0)
    end
    self.pngs[frame] = png.encode(image.upscale(capture.from_gd(data), config.upscale))
  end
  return self.pngs[frame]
end

function Worker:ask(job, result)
  local started = clock.now()
  local frames = {}
  for i, frame in ipairs(job.frames) do
    frames[i] = { png = self:png(frame.frame), seconds_ago = frame.seconds_ago }
  end
  result.encode_ms = elapsed_ms(started)

  local request = jev_policy.build({
    frames = frames,
    controller_now = job.controller_now,
    controller_history = job.controller_history,
    progress_recently = job.progress_recently,
    stuck = job.stuck,
    in_air = job.in_air,
    screen = job.screen,
  })
  started = clock.now()
  local response, err = self.client:systemone(request)
  result.latency_ms = elapsed_ms(started)
  if not response then
    result.error = err
    return
  end

  local answers = response.answers
  local controls = jev_policy.decode(answers)
  local diagnostics = {}
  for _, diagnostic in ipairs(jev_policy.DIAGNOSTICS) do
    local answer = answers[diagnostic[1]]
    diagnostics[diagnostic[1]] = answer and answer.noul
  end
  result.controls, result.diagnostics = controls, diagnostics
end

-- Posts and returns the job's result; a failure becomes the result's error instead of an exception.
function Worker:handle(job)
  local result = { seq = job.seq, frame = job.frame, worker = self.id }
  local ok, err = pcall(self.ask, self, job, result)
  if not ok then
    result.error = tostring(err)
  end

  local in_job = {}
  for _, frame in ipairs(job.frames) do
    in_job[frame.frame] = true
  end
  for frame in pairs(self.pngs) do
    if not in_job[frame] then
      self.pngs[frame] = nil
    end
  end

  self.box:post_result(job.seq, result)
  return result
end

-- Handles jobs until stop is requested or no job has arrived for idle_seconds.
function Worker:run()
  local idle_since = clock.now()
  while not self.box:stop_requested() do
    local job = self.box:claim_job(self.id)
    if job then
      self:handle(job)
      idle_since = clock.now()
    elseif clock.now() - idle_since > self.idle_seconds then
      return
    else
      clock.sleep(0.002)
    end
  end
end

if is_script then
  local id, exchange_dir, results_dir = arg[1], arg[2], arg[3]
  assert(id and exchange_dir and results_dir, "usage: luajit lua/worker.lua <worker_id> <exchange_dir> <results_dir>")
  worker.new({
    id = id,
    box = mailbox.open(exchange_dir, results_dir),
    client = typesafe.client({ model = config.model }),
  }):run()
  os.exit(0)
end

return worker
