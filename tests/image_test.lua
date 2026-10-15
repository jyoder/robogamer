local image = require("image")
local check = require("check")

local function two_by_two()
  local img = image.new(2, 2)
  image.set(img, 0, 0, 255, 0, 0)
  image.set(img, 1, 0, 0, 255, 0)
  image.set(img, 0, 1, 0, 0, 255)
  image.set(img, 1, 1, 9, 8, 7)
  return img
end

local function check_upscaled(factor)
  local src = two_by_two()
  local out = image.upscale(src, factor)
  check.eq(out.width, 2 * factor, "width")
  check.eq(out.height, 2 * factor, "height")
  for y = 0, out.height - 1 do
    for x = 0, out.width - 1 do
      local r, g, b = image.get(out, x, y)
      local sr, sg, sb = image.get(src, math.floor(x / factor), math.floor(y / factor))
      local at = string.format("pixel %d,%d", x, y)
      check.eq(r, sr, at .. " red")
      check.eq(g, sg, at .. " green")
      check.eq(b, sb, at .. " blue")
    end
  end
end

return {
  { "new images start black", function()
    local img = image.new(3, 2)
    for y = 0, 1 do
      for x = 0, 2 do
        local r, g, b = image.get(img, x, y)
        check.eq(r + g + b, 0, "pixel sum")
      end
    end
  end },
  { "upscale by 2 repeats each pixel in a 2x2 block", function()
    check_upscaled(2)
  end },
  { "upscale by 3 repeats each pixel in a 3x3 block", function()
    check_upscaled(3)
  end },
}
