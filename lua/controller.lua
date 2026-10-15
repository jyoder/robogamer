-- Holds the emulator's controller state between Jev answers and describes it back to Jev.
local controller = {}

controller.DPAD = {
  none = {},
  right = { right = true },
  left = { left = true },
  up = { up = true },
  down = { down = true },
  up_right = { up = true, right = true },
  up_left = { up = true, left = true },
  down_right = { down = true, right = true },
  down_left = { down = true, left = true },
}

-- Applied in this order, so simultaneous changes enter history in this order.
controller.BUTTONS = {
  { id = "a", key = "A", name = "A" },
  { id = "b", key = "B", name = "B" },
  { id = "start", key = "start", name = "Start" },
  { id = "select", key = "select", name = "Select" },
}

local DIRECTION_KEYS = { "up", "down", "left", "right" }
local FRAMES_PER_SECOND = 60
local OPTIONS = { "press_at", "release_at", "history_seconds", "allow_start_in_level" }

local NAMES = {}
for _, button in ipairs(controller.BUTTONS) do
  NAMES[button.id] = button.name
end

local function seconds(frames)
  return string.format("%.1f s", frames / FRAMES_PER_SECOND)
end

local function initial_state(frame)
  local state = { dpad = { value = "none", since_frame = frame } }
  for _, button in ipairs(controller.BUTTONS) do
    state[button.id] = { value = false, since_frame = frame }
  end
  return state
end

local function change_text(entry)
  if entry.control == "dpad" then
    return "dpad " .. entry.value
  end
  return NAMES[entry.control] .. (entry.value and " pressed" or " released")
end

local function set(self, control, value, frame)
  if self.state[control].value == value then
    return
  end
  self.state[control] = { value = value, since_frame = frame }
  self.history[#self.history + 1] = { frame = frame, control = control, value = value }
  local window = self.opts.history_seconds * FRAMES_PER_SECOND
  while frame - self.history[1].frame > window do
    table.remove(self.history, 1)
  end
end

local Controller = {}
Controller.__index = Controller

-- opts: { press_at, release_at, history_seconds, allow_start_in_level }, all required.
function controller.new(opts)
  for _, name in ipairs(OPTIONS) do
    assert(opts[name] ~= nil, "controller.new: missing option " .. name)
  end
  return setmetatable({ opts = opts, state = initial_state(0), history = {} }, Controller)
end

-- controls: { dpad = <DPAD option>, a = p, b = p, start = p, select = p }, p a probability 0..1.
-- screen: "title" | "playing" | "game_over"
function Controller:apply(controls, screen, frame)
  assert(controller.DPAD[controls.dpad], "controller: unknown dpad option " .. tostring(controls.dpad))
  set(self, "dpad", controls.dpad, frame)
  for _, button in ipairs(controller.BUTTONS) do
    local p = controls[button.id]
    local pressed = self.state[button.id].value
    if pressed then
      pressed = p >= self.opts.release_at
    else
      pressed = p > self.opts.press_at
    end
    -- Start pauses mid-level, which would freeze the game Jev is trying to play.
    if button.id == "start" and screen == "playing" and not self.opts.allow_start_in_level then
      pressed = false
    end
    set(self, button.id, pressed, frame)
  end
end

-- Returns how many frames the button has been held, or 0 when it is released.
function Controller:held_frames(control, frame)
  local state = self.state[control]
  return state.value and frame - state.since_frame or 0
end

function Controller:release(control, frame)
  set(self, control, false, frame)
end

function Controller:reset(frame)
  self.state = initial_state(frame)
  self.history = {}
end

-- Returns the table FCEUX joypad.set expects.
function Controller:joypad()
  local pad = {}
  for _, key in ipairs(DIRECTION_KEYS) do
    pad[key] = controller.DPAD[self.state.dpad.value][key] == true
  end
  for _, button in ipairs(controller.BUTTONS) do
    pad[button.key] = self.state[button.id].value
  end
  return pad
end

-- Returns controller_now, controller_history for jev_policy.build.
function Controller:describe(frame)
  local dpad = self.state.dpad
  local now = { dpad = dpad.value .. " for " .. seconds(frame - dpad.since_frame) }
  for _, button in ipairs(controller.BUTTONS) do
    local state = self.state[button.id]
    now[button.id] = (state.value and "held " or "released ") .. seconds(frame - state.since_frame)
  end

  local history = {}
  local window = self.opts.history_seconds * FRAMES_PER_SECOND
  for _, entry in ipairs(self.history) do
    if frame - entry.frame <= window then
      history[#history + 1] = seconds(frame - entry.frame) .. " ago: " .. change_text(entry)
    end
  end
  return now, history
end

return controller
