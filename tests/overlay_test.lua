local overlay = require("overlay")
local check = require("check")

local function recording_gui()
  local texts = {}
  local gui = { texts = texts }
  function gui.text(_, _, text)
    texts[#texts + 1] = text
  end
  function gui.box() end
  function gui.line() end
  return gui
end

local function drawn(gui)
  return table.concat(gui.texts, "\n")
end

local function result()
  return {
    frame = 100,
    controls = { dpad = "right", a = 0.72, b = 0.31, start = 0, select = 0 },
    diagnostics = { enemy_close_ahead = 0.12, gap_ahead = 0.8, obstacle_ahead = 0.05, mario_in_air = 0.1 },
    job = { died_near_here = { "was hit by an enemy", "fell into a pit" } },
  }
end

return {
  { "before any answer it says Jev is waiting", function()
    local gui = recording_gui()
    overlay.draw(gui, { frame = 1, keys = {}, press_at = 0.6, stuck = false })
    check.eq(drawn(gui):find("waiting", 1, true) ~= nil, true, drawn(gui))
  end },
  { "shows the direction, answer age, button probabilities and what Jev sees", function()
    local gui = recording_gui()
    overlay.draw(gui, { result = result(), frame = 112, keys = { A = true }, press_at = 0.6, stuck = true })
    local text = drawn(gui)
    for _, expected in ipairs({ "right", "12 frames old", "STUCK", "0.72", "0.31", "gap 0.80", "enemy 0.12" }) do
      check.eq(text:find(expected, 1, true) ~= nil, true, "missing " .. expected .. " in\n" .. text)
    end
  end },
  { "shows the newest death near here and how many there were", function()
    local gui = recording_gui()
    overlay.draw(gui, { result = result(), frame = 112, keys = {}, press_at = 0.6, stuck = false })
    check.eq(drawn(gui):find("died here: fell into a pit (x2)", 1, true) ~= nil, true, drawn(gui))
  end },
}
