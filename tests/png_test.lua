local ffi = require("ffi")
local image = require("image")
local png = require("png")
local check = require("check")

ffi.cdef([[
int uncompress(uint8_t *dest, unsigned long *destLen, const uint8_t *source, unsigned long sourceLen);
]])
local zlib = ffi.load("z")

local function u32(s, i)
  local a, b, c, d = s:byte(i, i + 3)
  return ((a * 256 + b) * 256 + c) * 256 + d
end

-- Splits a PNG into chunks, verifying each chunk's CRC.
local function read_chunks(data)
  check.eq(data:sub(1, 8), "\137PNG\r\n\26\n", "signature")
  local chunks, i = {}, 9
  while i <= #data do
    local len = u32(data, i)
    local kind = data:sub(i + 4, i + 7)
    local body = data:sub(i + 8, i + 7 + len)
    local crc = tonumber(zlib.crc32(0, ffi.cast("const uint8_t *", kind .. body), #kind + len))
    check.eq(u32(data, i + 8 + len), crc, kind .. " CRC")
    chunks[#chunks + 1] = { kind = kind, body = body }
    i = i + 12 + len
  end
  return chunks
end

local function inflate(data, len)
  local out = ffi.new("uint8_t[?]", len)
  local out_len = ffi.new("unsigned long[1]", len)
  check.eq(zlib.uncompress(out, out_len, ffi.cast("const uint8_t *", data), #data), 0, "uncompress result")
  check.eq(tonumber(out_len[0]), len, "inflated length")
  return ffi.string(out, len)
end

local function sample_image()
  local img = image.new(3, 2)
  image.set(img, 0, 0, 255, 0, 0)
  image.set(img, 1, 0, 0, 255, 0)
  image.set(img, 2, 0, 0, 0, 255)
  image.set(img, 0, 1, 1, 2, 3)
  image.set(img, 2, 1, 250, 251, 252)
  return img
end

return {
  { "chunks are IHDR, IDAT, IEND with valid CRCs", function()
    local chunks = read_chunks(png.encode(sample_image()))
    check.eq(#chunks, 3, "chunk count")
    check.eq(chunks[1].kind, "IHDR", "first chunk")
    check.eq(chunks[2].kind, "IDAT", "second chunk")
    check.eq(chunks[3].kind, "IEND", "third chunk")
  end },
  { "IHDR declares the size as 8-bit RGB", function()
    local ihdr = read_chunks(png.encode(sample_image()))[1].body
    check.eq(u32(ihdr, 1), 3, "width")
    check.eq(u32(ihdr, 5), 2, "height")
    check.eq(ihdr:sub(9), string.char(8, 2, 0, 0, 0), "depth, color type, compression, filter, interlace")
  end },
  { "IDAT holds unfiltered RGB scanlines", function()
    local img = sample_image()
    local idat = read_chunks(png.encode(img))[2].body
    local row_bytes = img.width * 3
    local raw = inflate(idat, (row_bytes + 1) * img.height)
    for y = 0, img.height - 1 do
      local line = raw:sub(y * (row_bytes + 1) + 1, (y + 1) * (row_bytes + 1))
      check.eq(line:byte(1), 0, "row " .. y .. " filter type")
      check.eq(line:sub(2), ffi.string(img.pixels + y * row_bytes, row_bytes), "row " .. y .. " pixels")
    end
  end },
}
