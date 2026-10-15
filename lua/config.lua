-- Tunables shared by the launcher, the emulator script and the workers.
return {
  model = "jev-preview",
  workers = 4,

  -- NES NTSC frame rate. The launcher paces the emulator at this rate.
  fps = 60.0988,

  -- A job is posted every call_every_frames frames, showing the frames this many frames ago.
  call_every_frames = 4,
  frames_ago = { 12, 0 },
  upscale = 2,

  -- Answers older than this are ignored; with none applied for answer_timeout_frames, A is released.
  max_staleness_frames = 20,
  answer_timeout_frames = 30,
  -- A held longer than this while Mario stands on the ground is released so it can be pressed again.
  grounded_a_frames = 10,

  controller = { press_at = 0.6, release_at = 0.4, history_seconds = 3, allow_start_in_level = false },
  tracker = { window_frames = 60, stuck_frames = 120, min_progress = 8 },

  max_run_seconds = 420,
  worker_idle_seconds = 30,
  exchange_dir = "tmp",
  runs_dir = "runs",
}
