local typesafe = require("typesafe")
local check = require("check")

local function base64(s)
  return typesafe.png_asset(s).data_base64
end

return {
  { "png_asset describes a PNG image", function()
    local asset = typesafe.png_asset("x")
    check.eq(asset.type, "image", "type")
    check.eq(asset.format, "png", "format")
  end },
  { "base64 matches RFC 4648 test vectors", function()
    for input, expected in pairs({
      [""] = "",
      f = "Zg==",
      fo = "Zm8=",
      foo = "Zm9v",
      foob = "Zm9vYg==",
      fooba = "Zm9vYmE=",
      foobar = "Zm9vYmFy",
    }) do
      check.eq(base64(input), expected, string.format("base64(%q)", input))
    end
  end },
  { "base64 handles high and zero bytes", function()
    check.eq(base64("\255\254\253"), "//79", "high bytes")
    check.eq(base64("\0\0\0\0"), "AAAAAA==", "zero bytes")
  end },
}
