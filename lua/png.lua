-- Encodes RGB images (see image.lua) as PNG using the system zlib.
local ffi = require("ffi")
local bit = require("bit")

ffi.cdef([[
unsigned long compressBound(unsigned long sourceLen);
int compress2(uint8_t *dest, unsigned long *destLen, const uint8_t *source, unsigned long sourceLen, int level);
unsigned long crc32(unsigned long crc, const uint8_t *buf, unsigned int len);
]])
local zlib = ffi.load("z")

local png = {}

local SIGNATURE = "\137PNG\r\n\26\n"
local BIT_DEPTH, COLOR_TYPE_RGB = 8, 2

local function be32(n)
  return string.char(
    bit.band(bit.rshift(n, 24), 0xff),
    bit.band(bit.rshift(n, 16), 0xff),
    bit.band(bit.rshift(n, 8), 0xff),
    bit.band(n, 0xff)
  )
end

local function chunk(kind, data)
  local body = kind .. data
  local crc = zlib.crc32(0, ffi.cast("const uint8_t *", body), #body)
  return be32(#data) .. body .. be32(tonumber(crc))
end

-- Each scanline is a filter-type byte (0, no filter) followed by the row's RGB bytes.
local function scanlines(img)
  local row_bytes = img.width * 3
  local len = (row_bytes + 1) * img.height
  local raw = ffi.new("uint8_t[?]", len)
  for y = 0, img.height - 1 do
    ffi.copy(raw + y * (row_bytes + 1) + 1, img.pixels + y * row_bytes, row_bytes)
  end
  return raw, len
end

local function deflate(data, len)
  local bound = zlib.compressBound(len)
  local out = ffi.new("uint8_t[?]", bound)
  local out_len = ffi.new("unsigned long[1]", bound)
  local rc = zlib.compress2(out, out_len, data, len, 6)
  assert(rc == 0, "zlib compress2 failed: " .. rc)
  return ffi.string(out, out_len[0])
end

function png.encode(img)
  return table.concat({
    SIGNATURE,
    chunk("IHDR", be32(img.width) .. be32(img.height) .. string.char(BIT_DEPTH, COLOR_TYPE_RGB, 0, 0, 0)),
    chunk("IDAT", deflate(scanlines(img))),
    chunk("IEND", ""),
  })
end

return png
