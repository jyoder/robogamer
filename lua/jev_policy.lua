-- Asks Jev to set the controller: builds the System One request and decodes its answers.
local typesafe = require("typesafe")

local jev_policy = {}

-- Sent in this order; Jev can favor earlier Choice options.
jev_policy.DPAD = {
  { "none", "Press no direction. Mario stands still, or keeps drifting if he is in the air." },
  { "right", "Walk or run toward the right side of the screen. This is the direction of progress through the level." },
  { "left", "Walk or run toward the left side of the screen, away from the goal." },
  { "up", "Press up. This only matters when climbing a vine." },
  { "down", "Crouch, or enter a pipe that Mario is standing on top of." },
  { "up_right", "Up and right together. Behaves like right except when climbing a vine." },
  { "up_left", "Up and left together. Behaves like left except when climbing a vine." },
  { "down_right", "Down and right together. Behaves like crouching." },
  { "down_left", "Down and left together. Behaves like crouching." },
}

jev_policy.BUTTONS = {
  { "a", "The A button makes Mario jump, and holding it while he rises makes the jump higher and longer. In the newest frame in `frames`, does Mario need to be jumping now? Yes when he is about to run into an enemy such as a Goomba or Koopa, or be stopped by a pipe or wall ahead of him. Yes when a gap or pit in the ground is coming up ahead of him: he has to jump early, before he reaches its edge, because the controller responds a moment late. Also yes while Mario is rising in a jump. No when the ground ahead of Mario is clear. `died_near_here` lists how Mario already died around this spot; if it is not empty, what Mario did last time here did not work." },
  { "b", "Should the B button be held down right now? Holding B makes Mario run faster, which lets him jump farther. With the fire flower power-up, pressing B throws a fireball." },
  { "start", "Should the Start button be held down right now? Start begins the game from the title screen and pauses or unpauses during play." },
  { "select", "Should the Select button be held down right now? Select chooses between one and two players on the title screen and does nothing during play." },
}

-- Logged to explain bad decisions; never used to set the controller.
jev_policy.DIAGNOSTICS = {
  { "enemy_close_ahead", "In the newest frame in `frames`, is an enemy such as a Goomba or Koopa close to Mario on his right side, about to reach him?" },
  { "gap_ahead", "In the newest frame in `frames`, is there a gap or pit in the ground just to the right of Mario?" },
  { "obstacle_ahead", "In the newest frame in `frames`, is a pipe, wall or block stack directly to the right of Mario, blocking him from walking forward?" },
  { "mario_visible", "Is Mario visible in the newest frame in `frames`?" },
  { "mario_in_air", "In the newest frame in `frames`, is Mario in the air (jumping or falling) rather than standing on the ground or a block?" },
}

local GAME = "Super Mario Bros. on the NES. Mario must move right through the level, avoiding enemies and pits."
local DPAD_INSTRUCTIONS = "Which direction should be held on the controller's direction pad right now, based on the newest frame in `frames`, how things are moving across `frames`, and `controller_now`?"

local function dpad_criteria()
  local criteria, order = {}, {}
  for i, option in ipairs(jev_policy.DPAD) do
    criteria[option[1]] = option[2]
    order[i] = option[1]
  end
  return setmetatable(criteria, { __jsonorder = order })
end

local function frame_label(seconds_ago)
  return seconds_ago == 0 and "now" or string.format("%.2f seconds ago", seconds_ago)
end

-- observation:
--   frames: array of { png = <PNG bytes>, seconds_ago = number }, oldest first
--   controller_now: table of button name -> text, e.g. { dpad = "right, held 1.2 s", a = "released" }
--   controller_history: array of text, e.g. { "0.4 s ago: A pressed" }, oldest first
--   progress_recently: "moved_right" | "no_progress" | "moved_left"
--   stuck, in_air: booleans
--   screen: "title" | "playing" | "game_over"
--   died_near_here: array of text, e.g. { "fell into a pit" }, oldest first
-- Returns a request for typesafe Client:systemone.
function jev_policy.build(observation)
  local frames, assets = {}, {}
  for i, frame in ipairs(observation.frames) do
    local ref = string.format("@@frame-%d@@", i)
    frames[i] = { taken = frame_label(frame.seconds_ago), image = ref }
    assets[ref] = typesafe.png_asset(frame.png)
  end

  local questions = { dpad = { type = "choice", instructions = DPAD_INSTRUCTIONS, criteria = dpad_criteria() } }
  for _, list in ipairs({ jev_policy.BUTTONS, jev_policy.DIAGNOSTICS }) do
    for _, question in ipairs(list) do
      questions[question[1]] = { type = "noul", instructions = question[2] }
    end
  end

  return {
    state = {
      game = GAME,
      frames = frames,
      controller_now = observation.controller_now,
      controller_history = observation.controller_history,
      progress_recently = observation.progress_recently,
      stuck = observation.stuck,
      in_air = observation.in_air,
      screen = observation.screen,
      died_near_here = observation.died_near_here,
    },
    questions = questions,
    assets = assets,
  }
end

-- Returns { dpad = <option id>, a = <probability>, b = ..., start = ..., select = ... }.
function jev_policy.decode(answers)
  local controls = { dpad = answers.dpad.choice }
  for _, button in ipairs(jev_policy.BUTTONS) do
    controls[button[1]] = answers[button[1]].noul
  end
  return controls
end

return jev_policy
