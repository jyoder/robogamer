-- RGB images backed by FFI byte buffers: pixels[(y * width + x) * 3 + channel].
local ffi = require("ffi")

local image = {}

function image.new(width, height)
  return { width = width, height = height, pixels = ffi.new("uint8_t[?]", width * height * 3) }
end

function image.set(img, x, y, r, g, b)
  local i = (y * img.width + x) * 3
  img.pixels[i], img.pixels[i + 1], img.pixels[i + 2] = r, g, b
end

function image.get(img, x, y)
  local i = (y * img.width + x) * 3
  return img.pixels[i], img.pixels[i + 1], img.pixels[i + 2]
end

-- Nearest-neighbor upscale by a whole-number factor, which keeps pixel art sharp.
function image.upscale(img, factor)
  local out = image.new(img.width * factor, img.height * factor)
  local src_row_bytes, dst_row_bytes = img.width * 3, out.width * 3
  for y = 0, img.height - 1 do
    local src = img.pixels + y * src_row_bytes
    local dst = out.pixels + y * factor * dst_row_bytes
    for x = 0, img.width - 1 do
      for copy = 0, factor - 1 do
        ffi.copy(dst + (x * factor + copy) * 3, src + x * 3, 3)
      end
    end
    for copy = 1, factor - 1 do
      ffi.copy(dst + copy * dst_row_bytes, dst, dst_row_bytes)
    end
  end
  return out
end

return image
