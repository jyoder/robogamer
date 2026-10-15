-- Draws Jev's latest answer over the game screen for whoever is watching. Jev's own screenshots
-- read the emulator's frame without it.
local overlay = {}

local LEFT, TOP, LINE = 4, 34, 9
local BAR_WIDTH = 40
local PANEL = "#000000a0"
local HELD, RELEASED = "#30d050ff", "#909090ff"

local function bar(gui, x, y, label, p, held, press_at)
  local color = held and HELD or RELEASED
  gui.text(x, y, label)
  local left = x + 8
  gui.box(left, y + 1, left + BAR_WIDTH, y + 7, "#00000000", "white")
  gui.box(left, y + 1, left + math.floor(p * BAR_WIDTH), y + 7, color, color)
  local tick = left + math.floor(press_at * BAR_WIDTH)
  gui.line(tick, y, tick, y + 8, "red")
  gui.text(left + BAR_WIDTH + 4, y, string.format("%.2f", p))
end

-- gui: FCEUX's gui table, or anything with text, box and line.
-- view: { result = <latest applied worker result or nil>, keys = <held buttons>, press_at }
function overlay.draw(gui, view)
  local result = view.result
  local died = result and result.job and result.job.died_near_here or {}
  local lines = #died > 0 and 2 or 1
  gui.box(LEFT - 2, TOP - 2, 253, TOP + lines * LINE, PANEL, PANEL)

  if not result then
    gui.text(LEFT, TOP, "waiting for Jev")
    return
  end
  local controls = result.controls
  gui.text(LEFT, TOP, controls.dpad)
  bar(gui, LEFT + 64, TOP, "A", controls.a, view.keys.A, view.press_at)
  bar(gui, LEFT + 156, TOP, "B", controls.b, view.keys.B, view.press_at)

  if #died > 0 then
    gui.text(LEFT, TOP + LINE, "died here: " .. died[#died] .. (#died > 1 and string.format(" (x%d)", #died) or ""))
  end
end

return overlay
