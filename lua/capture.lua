-- Decodes the screenshots FCEUX's gui.gdscreenshot() returns (libgd's truecolor .gd format) into images.
local ffi = require("ffi")
local image = require("image")

local capture = {}

-- Signature 0xFF 0xFE, width and height as big-endian 16-bit, truecolor flag, transparent color.
local HEADER_BYTES = 11

-- Each pixel is 4 bytes: an unused byte, then R, G, B.
function capture.from_gd(data)
  assert(data:byte(1) == 0xff and data:byte(2) == 0xfe, "gd screenshot: bad signature")
  assert(data:byte(7) == 1, "gd screenshot: not truecolor")
  local width = data:byte(3) * 256 + data:byte(4)
  local height = data:byte(5) * 256 + data:byte(6)
  local expected = HEADER_BYTES + width * height * 4
  if #data ~= expected then
    error(string.format("gd screenshot: %dx%d needs %d bytes, got %d", width, height, expected, #data), 2)
  end

  local img = image.new(width, height)
  local src = ffi.cast("const uint8_t *", data) + HEADER_BYTES
  local dst = img.pixels
  for i = 0, width * height - 1 do
    dst[i * 3], dst[i * 3 + 1], dst[i * 3 + 2] = src[i * 4 + 1], src[i * 4 + 2], src[i * 4 + 3]
  end
  return img
end

return capture
