-- TypeSafe System One client over libcurl. One client keeps one connection open across requests.
local ffi = require("ffi")
local bit = require("bit")
local json = require("vendor.dkjson")

ffi.cdef([[
typedef void CURL;
struct curl_slist;
int curl_global_init(long flags);
CURL *curl_easy_init(void);
void curl_easy_cleanup(CURL *curl);
int curl_easy_setopt(CURL *curl, int option, ...);
int curl_easy_perform(CURL *curl);
int curl_easy_getinfo(CURL *curl, int info, ...);
const char *curl_easy_strerror(int code);
struct curl_slist *curl_slist_append(struct curl_slist *list, const char *value);
void curl_slist_free_all(struct curl_slist *list);
typedef size_t (*curl_write_callback)(char *data, size_t size, size_t count, void *userdata);
]])
local curl = ffi.load("curl")

local CURL_GLOBAL_DEFAULT = 3
local CURLOPT_URL = 10002
local CURLOPT_POSTFIELDS = 10015
local CURLOPT_HTTPHEADER = 10023
local CURLOPT_WRITEFUNCTION = 20011
local CURLOPT_POSTFIELDSIZE = 60
local CURLOPT_HTTP_VERSION = 84
local CURLOPT_NOSIGNAL = 99
local CURLOPT_TIMEOUT_MS = 155
local CURL_HTTP_VERSION_2TLS = 4
local CURLINFO_RESPONSE_CODE = 0x200002

local URL = "https://api.typesafe.ai/v1/systemone"
local TIMEOUT_MS = 5000

assert(curl.curl_global_init(CURL_GLOBAL_DEFAULT) == 0, "curl_global_init failed")

local typesafe = {}

local BASE64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function base64(data)
  local out = {}
  for i = 1, #data, 3 do
    local a, b, c = data:byte(i, i + 2)
    local n = bit.bor(bit.lshift(a, 16), bit.lshift(b or 0, 8), c or 0)
    local quad = {}
    for k = 1, 4 do
      local index = bit.band(bit.rshift(n, (4 - k) * 6), 63) + 1
      quad[k] = BASE64:sub(index, index)
    end
    if not b then
      quad[3] = "="
    end
    if not c then
      quad[4] = "="
    end
    out[#out + 1] = table.concat(quad)
  end
  return table.concat(out)
end

-- A request asset for a PNG, to be referenced from state, instructions or criteria.
function typesafe.png_asset(png_bytes)
  return { type = "image", format = "png", data_base64 = base64(png_bytes) }
end

local Client = {}
Client.__index = Client

-- opts.model: model ID or alias sent with every request.
function typesafe.client(opts)
  local api_key = os.getenv("TYPESAFE_API_KEY")
  assert(api_key and api_key ~= "", "TYPESAFE_API_KEY is not set (mise loads it from .env)")

  local handle = ffi.gc(curl.curl_easy_init(), curl.curl_easy_cleanup)
  assert(handle ~= nil, "curl_easy_init failed")

  local headers = nil
  for _, header in ipairs({
    "Content-Type: application/json",
    "Authorization: Bearer " .. api_key,
    "TypeSafe-Danger-Zone-Images: true",
  }) do
    headers = curl.curl_slist_append(headers, header)
  end
  headers = ffi.gc(headers, curl.curl_slist_free_all)

  local self = setmetatable({ model = opts.model, handle = handle, headers = headers, chunks = {} }, Client)
  self.on_write = ffi.cast("curl_write_callback", function(data, size, count)
    local len = tonumber(size * count)
    self.chunks[#self.chunks + 1] = ffi.string(data, len)
    return len
  end)

  curl.curl_easy_setopt(handle, CURLOPT_URL, URL)
  curl.curl_easy_setopt(handle, CURLOPT_HTTPHEADER, headers)
  curl.curl_easy_setopt(handle, CURLOPT_WRITEFUNCTION, self.on_write)
  curl.curl_easy_setopt(handle, CURLOPT_HTTP_VERSION, ffi.cast("long", CURL_HTTP_VERSION_2TLS))
  curl.curl_easy_setopt(handle, CURLOPT_NOSIGNAL, ffi.cast("long", 1))
  curl.curl_easy_setopt(handle, CURLOPT_TIMEOUT_MS, ffi.cast("long", TIMEOUT_MS))
  return self
end

-- request: { state, questions, assets } as in the HTTP API; the client adds the model.
-- Returns the decoded response, or nil and an error message.
function Client:systemone(request)
  local body = json.encode({
    model = self.model,
    state = request.state,
    questions = request.questions,
    assets = request.assets,
  })
  self.chunks = {}
  curl.curl_easy_setopt(self.handle, CURLOPT_POSTFIELDS, body)
  curl.curl_easy_setopt(self.handle, CURLOPT_POSTFIELDSIZE, ffi.cast("long", #body))

  local rc = curl.curl_easy_perform(self.handle)
  if rc ~= 0 then
    return nil, "curl: " .. ffi.string(curl.curl_easy_strerror(rc))
  end

  local status = ffi.new("long[1]")
  curl.curl_easy_getinfo(self.handle, CURLINFO_RESPONSE_CODE, status)
  local text = table.concat(self.chunks)
  local response, _, decode_err = json.decode(text)
  if tonumber(status[0]) ~= 200 then
    local message = type(response) == "table" and json.encode(response.error or response) or text
    return nil, string.format("HTTP %d: %s", tonumber(status[0]), message)
  end
  if type(response) ~= "table" then
    return nil, "invalid JSON response: " .. tostring(decode_err)
  end
  return response
end

-- libcurl calls back into Lua during curl_easy_perform, which LuaJIT only allows from interpreted code.
jit.off(Client.systemone)

return typesafe
