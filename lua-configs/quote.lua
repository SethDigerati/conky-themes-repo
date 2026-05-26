-- Quote Lua Script for Conky
-- Fetches today's quote from zenquotes.io/api/today, caches it,
-- downloads the API-provided author image when present, falls back
-- to UI Avatars, and exposes Conky getters.

local script_dir = debug.getinfo(1, "S").source:match("^@(.*/)")
if not script_dir then script_dir = "./" end

local function add_package_path(p)
    if package and package.path and not package.path:find(p, 1, true) then
        package.path = package.path .. ";" .. p
    end
end

local function add_package_cpath(p)
    if package and package.cpath and not package.cpath:find(p, 1, true) then
        package.cpath = package.cpath .. ";" .. p
    end
end

-- Repo-local modules
add_package_path(script_dir .. "../?.lua")
add_package_path(script_dir .. "../config/?.lua")

-- Common system module dirs across Lua versions
local versions = {"5.1", "5.2", "5.3", "5.4", "5.5"}
for _, v in ipairs(versions) do
    add_package_path("/usr/share/lua/" .. v .. "/?.lua")
    add_package_path("/usr/share/lua/" .. v .. "/?/init.lua")
    add_package_path("/usr/local/share/lua/" .. v .. "/?.lua")
    add_package_path("/usr/local/share/lua/" .. v .. "/?/init.lua")
    add_package_cpath("/usr/lib/lua/" .. v .. "/?.so")
    add_package_cpath("/usr/local/lib/lua/" .. v .. "/?.so")
end

-- Try to find a JSON backend
local json = nil
local json_backend = nil
do
    local ok, mod = pcall(require, "dkjson")
    if ok then
        json = mod
        json_backend = "dkjson"
    else
        ok, mod = pcall(require, "cjson.safe")
        if ok then
            json = mod
            json_backend = "cjson"
        else
            ok, mod = pcall(require, "cjson")
            if ok then
                json = mod
                json_backend = "cjson"
            end
        end
    end
end

local function json_decode(s)
    if not json then
        return nil, nil, "No JSON library found"
    end
    if json_backend == "dkjson" then
        return json.decode(s)
    end
    local ok, res = pcall(json.decode, s)
    if ok then return res end
    return nil, nil, res
end

local function json_encode(t)
    if not json then return "{}" end
    if json_backend == "dkjson" then
        return json.encode(t, {indent = false})
    end
    local ok, res = pcall(json.encode, t)
    if ok then return res end
    return "{}"
end

-- Load api-config if available
local api_config = nil
do
    local ok, mod = pcall(require, "api-config")
    if ok then api_config = mod end
end

-- Helpers for data dir resolution
local function temp_base_dir()
    return os.getenv("TMPDIR") or os.getenv("XDG_RUNTIME_DIR") or "/tmp"
end

local function make_session_data_dir()
    math.randomseed(os.time())
    local uid = os.getenv("UID") or ""
    return temp_base_dir() .. "/conky-quote-" .. os.time() .. "-" .. math.random(100000, 999999) .. (uid ~= "" and ("-" .. uid) or "")
end

local function resolve_data_dir()
    local env_dir = os.getenv("CONKY_QUOTE_DATA_DIR")
    if env_dir and env_dir ~= "" then return env_dir end
    if _G.CONKY_QUOTE_DATA_DIR and _G.CONKY_QUOTE_DATA_DIR ~= "" then return _G.CONKY_QUOTE_DATA_DIR end
    if type(conky_parse) == "function" then
        local parsed = conky_parse("${template1}")
        if parsed and parsed ~= "" and parsed ~= "${template1}" then return parsed end
    end
    return "/tmp/conky-quote"
end

local DATA_DIR = resolve_data_dir()
_G.CONKY_QUOTE_DATA_DIR = DATA_DIR
local RAW_JSON = DATA_DIR .. "/raw.json"
local LOG_FILE = DATA_DIR .. "/debug.log"
local AUTHOR_IMAGE = DATA_DIR .. "/author.png"

-- Find curl binary (copied pattern)
local function find_curl()
    local handle = io.popen("command -v curl 2>/dev/null")
    if handle then
        local path = handle:read("*l")
        handle:close()
        if path and path ~= "" then return path end
    end
    local f = io.open("/usr/bin/curl", "r")
    if f then f:close(); return "/usr/bin/curl" end
    f = io.open("/bin/curl", "r")
    if f then f:close(); return "/bin/curl" end
    return "curl"
end

local curl = find_curl()

local function exec_ok(cmd)
    local r1, _, r3 = os.execute(cmd)
    if type(r1) == "boolean" then return r1 end
    if type(r1) == "number" then return r1 == 0 end
    if type(r3) == "number" then return r3 == 0 end
    return false
end

local function log(msg)
    local f = io.open(LOG_FILE, "a")
    if f then f:write(os.date("[%Y-%m-%d %H:%M:%S] ") .. tostring(msg) .. "\n"); f:close() end
end

-- Check connectivity by probing the quotes endpoint
local function check_internet()
    local probe = "https://zenquotes.io/api/today"
    local cmd = string.format('"%s" -s -S --connect-timeout 3 --max-time 5 -o /dev/null "%s" 2>/dev/null', curl, probe)
    return exec_ok(cmd)
end

-- Ensure data dir exists (fall back to session dir when necessary)
if not exec_ok("mkdir -p \"" .. DATA_DIR .. "\"") then
    local fallback = make_session_data_dir()
    if exec_ok("mkdir -p \"" .. fallback .. "\"") then
        DATA_DIR = fallback
        _G.CONKY_QUOTE_DATA_DIR = DATA_DIR
        RAW_JSON = DATA_DIR .. "/raw.json"
        LOG_FILE = DATA_DIR .. "/debug.log"
        AUTHOR_IMAGE = DATA_DIR .. "/author.png"
    end
end

log("Starting Quote script, caching to: " .. DATA_DIR)
log("curl binary: " .. tostring(curl))
if json_backend then log("JSON backend: " .. tostring(json_backend)) else log("WARNING: No JSON backend found") end

-- Runtime storage
local quote_data = {
    last_update = 0,
    quote = "",
    author = "",
    author_image_url = nil,
    author_image_path = "",
    raw_date = nil,
    update_time = "N/A"
}

local function get_update_interval()
    if api_config and api_config.quote and api_config.quote.UPDATE_INTERVAL then
        return tonumber(api_config.quote.UPDATE_INTERVAL) or 86400
    end
    if api_config and api_config.weather and api_config.weather.UPDATE_INTERVAL then
        return tonumber(api_config.weather.UPDATE_INTERVAL) or 86400
    end
    return 86400
end

local function url_encode(s)
    if not s then return "" end
    return (s:gsub("([^%w%-%_%.%~ ])", function(c) return string.format("%%%02X", string.byte(c)) end):gsub(" ", "+"))
end

local function download_image_to_final(url)
    if not url or url == "" then return false end
    local staging = AUTHOR_IMAGE .. ".tmp"
    local cmd = string.format('"%s" -s -S --connect-timeout 5 --max-time 10 -o "%s" "%s" 2>/dev/null && mv "%s" "%s"', curl, staging, url, staging, AUTHOR_IMAGE)
    if exec_ok(cmd) then
        quote_data.author_image_path = AUTHOR_IMAGE
        return true
    end
    return false
end

local function download_avatar_fallback(name)
    local safe = url_encode(name or "Unknown")
    local avatar_url = string.format('https://ui-avatars.com/api/?name=%s&size=256&background=000000&color=ffffff&format=png', safe)
    return download_image_to_final(avatar_url)
end

local function parse_content(content)
    if not content or content == "" then return false end

    local data, _, err = json_decode(content)
    if data then
        local obj = nil
        if type(data) == "table" then
            if #data >= 1 then obj = data[1] else obj = data end
        end
        if obj then
            quote_data.quote = obj.q or obj.quote or quote_data.quote
            quote_data.author = obj.a or obj.author or quote_data.author
            quote_data.author_image_url = obj.i or obj.image or nil
            quote_data.raw_date = obj.date or quote_data.raw_date
            return true
        end
    end

    -- Conservative fallback parsing
    local q = content:match('"q"%s*:%s*"(.-)"') or content:match('"quote"%s*:%s*"(.-)"')
    local a = content:match('"a"%s*:%s*"(.-)"') or content:match('"author"%s*:%s*"(.-)"')
    local i = content:match('"i"%s*:%s*"(.-)"') or content:match('"image"%s*:%s*"(.-)"')
    if q or a or i then
        -- Unescape simple escapes
        if q then q = q:gsub('\\"', '"'):gsub('\\n', '\n') end
        if a then a = a:gsub('\\"', '"') end
        quote_data.quote = q or quote_data.quote
        quote_data.author = a or quote_data.author
        quote_data.author_image_url = i or quote_data.author_image_url
        return true
    end

    return false
end

local function fetch_and_update()
    local zen_url = "https://zenquotes.io/api/today"
    local env_key = os.getenv("ZENQUOTES_API_KEY")
    if (not env_key or env_key == "") and api_config and api_config.quote and api_config.quote.API_KEY then
        env_key = api_config.quote.API_KEY
    end
    if env_key and env_key ~= "" then
        -- Append as token param if set (ZenQuotes uses a token param in some setups)
        zen_url = zen_url .. "?token=" .. url_encode(env_key)
    end

    local temp_raw = RAW_JSON .. ".tmp"
    local cmd = string.format('"%s" -s -S --connect-timeout 5 --max-time 10 -o "%s" "%s" 2>/dev/null && mv "%s" "%s"', curl, temp_raw, zen_url, temp_raw, RAW_JSON)
    if not exec_ok(cmd) then
        log("curl fetch failed for quote")
        return false
    end

    local f = io.open(RAW_JSON, "r")
    if not f then log("raw.json missing after fetch"); return false end
    local content = f:read("*a")
    f:close()
    if not content or content == "" then log("raw.json empty after fetch"); return false end

    if not parse_content(content) then
        log("Failed to parse quote JSON")
        return false
    end

    local ok_image = false
    if quote_data.author_image_url and quote_data.author_image_url ~= "" then
        ok_image = download_image_to_final(quote_data.author_image_url)
        if not ok_image then
            log("Failed to download API-provided image, falling back to avatar service")
        end
    end

    if not ok_image then
        ok_image = download_avatar_fallback(quote_data.author or "Unknown")
    end

    -- Apply left-edge fade with ImageMagick (silent no-op if not installed)
    if ok_image then
        local fade_cmd = string.format(
            'magick "%s" -alpha on ( +clone -alpha extract -fx "min(1,i/(w*0.3))" ) -compose copy_opacity -composite "png:%s.tmp" && mv "%s.tmp" "%s"',
            AUTHOR_IMAGE, AUTHOR_IMAGE, AUTHOR_IMAGE, AUTHOR_IMAGE
        )
        exec_ok(fade_cmd)
    end

    quote_data.last_update = os.time()
    quote_data.update_time = os.date("%Y-%m-%d %H:%M:%S", quote_data.last_update)
    return true
end

-- Load cached data from disk so we display something immediately
local cache_file = io.open(RAW_JSON, "r")
if cache_file then
    local content = cache_file:read("*a")
    cache_file:close()
    if content and content ~= "" then
        if parse_content(content) then
            quote_data.last_update = os.time()
            quote_data.update_time = os.date("%Y-%m-%d %H:%M:%S", quote_data.last_update)
            log("Loaded cached quote")
        end
    end
end

-- Public Conky hook - will fetch only when TTL expired
function conky_update_quote()
    local now = os.time()
    local ttl = get_update_interval()
    if (now - quote_data.last_update) < ttl and quote_data.quote and quote_data.quote ~= "" then
        return
    end

    if not check_internet() then
        log("No internet - skipping quote update")
        return
    end

    local ok = fetch_and_update()
    if not ok then log("fetch_and_update failed") end
end

-- Conky getters
function conky_quote()
    -- Wrap quote text at 50 characters per line (word-safe wrap)
    local function wrap_paragraph(par, width)
        local parts = {}
        local cur = ""
        for word in par:gmatch("%S+") do
            local wlen = #word
            if cur == "" then
                if wlen > width then
                    -- split long word
                    local s = 1
                    while s <= wlen do
                        table.insert(parts, word:sub(s, s + width - 1))
                        s = s + width
                    end
                else
                    cur = word
                end
            else
                if #cur + 1 + wlen <= width then
                    cur = cur .. " " .. word
                else
                    table.insert(parts, cur)
                    if wlen > width then
                        local s = 1
                        while s <= wlen do
                            table.insert(parts, word:sub(s, s + width - 1))
                            s = s + width
                        end
                        cur = ""
                    else
                        cur = word
                    end
                end
            end
        end
        if cur ~= "" then table.insert(parts, cur) end
        return table.concat(parts, "\n")
    end

    local function wrap_text(text, width)
        if not text or text == "" then return "" end
        width = tonumber(width) or 50
        local out = {}
        for line in (text .. "\n"):gmatch("(.-)\n") do
            table.insert(out, wrap_paragraph(line, width))
        end
        return table.concat(out, "\n")
    end

    return tostring(wrap_text(quote_data.quote or "", 40))
end

function conky_quote_author()
    return tostring(quote_data.author or "")
end

function conky_quote_author_image()
    return tostring(quote_data.author_image_path or "")
end

function conky_quote_update_time()
    return tostring(quote_data.update_time or "")
end

-- Return module table for require() users (not used by Conky directly)
return { _NAME = "quote" }
