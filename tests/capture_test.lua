local image = require("image")
local capture = require("capture")
local check = require("check")

local function gd(width, height, pixels, truecolor_flag)
  local header = string.char(
    0xff, 0xfe,
    math.floor(width / 256), width % 256,
    math.floor(height / 256), height % 256,
    truecolor_flag or 1,
    0xff, 0xff, 0xff, 0xff
  )
  local body = {}
  for i, rgb in ipairs(pixels) do
    body[i] = string.char(0, rgb[1], rgb[2], rgb[3])
  end
  return header .. table.concat(body)
end

local SAMPLE = {
  { 0x5d, 0x96, 0xff }, { 255, 0, 0 }, { 0, 255, 0 },
  { 0, 0, 255 }, { 1, 2, 3 }, { 250, 251, 252 },
}

local function check_error(fn, expected, label)
  local ok, err = pcall(fn)
  check.eq(ok, false, label .. " fails")
  assert(tostring(err):find(expected, 1, true), label .. ": unexpected error " .. tostring(err))
end

return {
  { "every pixel is read row-major as R, G, B", function()
    local img = capture.from_gd(gd(3, 2, SAMPLE))
    check.eq(img.width, 3, "width")
    check.eq(img.height, 2, "height")
    for i, rgb in ipairs(SAMPLE) do
      local x, y = (i - 1) % 3, math.floor((i - 1) / 3)
      local r, g, b = image.get(img, x, y)
      local at = string.format("pixel (%d, %d)", x, y)
      check.eq(r, rgb[1], at .. " red")
      check.eq(g, rgb[2], at .. " green")
      check.eq(b, rgb[3], at .. " blue")
    end
  end },
  { "width and height are big-endian", function()
    local pixels = {}
    for i = 1, 258 do
      pixels[i] = { i % 256, 0, 0 }
    end
    local img = capture.from_gd(gd(258, 1, pixels))
    check.eq(img.width, 258, "width")
    check.eq(img.height, 1, "height")
    check.eq((image.get(img, 257, 0)), 2, "last pixel red")
  end },
  { "a wrong signature is rejected", function()
    check_error(function() capture.from_gd("\0\0" .. gd(3, 2, SAMPLE):sub(3)) end, "bad signature", "signature")
  end },
  { "a palette screenshot is rejected", function()
    check_error(function() capture.from_gd(gd(3, 2, SAMPLE, 0)) end, "not truecolor", "palette flag")
  end },
  { "a length that does not match the size is rejected", function()
    check_error(function() capture.from_gd(gd(3, 2, SAMPLE):sub(1, -2)) end, "3x2 needs 35 bytes, got 34", "short data")
  end },
}
