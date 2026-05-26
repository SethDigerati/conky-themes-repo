-- IP info fetcher for network widget
-- Fetches public IP, ISP, timezone, latency from ipinfo.io and ping

local DATA_BASE = "/tmp/conky"
local CURL = "/usr/bin/curl"

local TTL = { ipinfo = 600, ping = 15 }
local last_fetch = { ipinfo = 0, ping = 0 }

-- Helpers
local function ensure_dir(path)
    os.execute("mkdir -p \"" .. path .. "\" 2>/dev/null")
end

local function write_file(path, content)
    local tmp = path .. ".tmp"
    local f = io.open(tmp, "w")
    if not f then return false end
    f:write(content)
    f:close()
    os.rename(tmp, path)
    return true
end

local function read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local c = f:read("*a")
    f:close()
    return c
end

local function run(cmd)
    local f = io.popen(cmd)
    if not f then return "" end
    local s = f:read("*a")
    f:close()
    return s
end

local function esc_json(s)
    if not s then return "" end
    return s:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r')
end

local function encode_json(val, indent)
    indent = indent or 0
    local pad = string.rep(" ", indent)
    local pad2 = string.rep(" ", indent + 2)
    local t = type(val)
    if t == "nil" then return "null"
    elseif t == "boolean" then return tostring(val)
    elseif t == "number" then return tostring(val)
    elseif t == "string" then return '"' .. esc_json(val) .. '"'
    elseif t == "table" then
        local keys, is_arr = {}, true
        for k in pairs(val) do table.insert(keys, k); if type(k) ~= "number" then is_arr = false end end
        table.sort(keys, function(a, b)
            if type(a) == type(b) then return a < b end
            return type(a) < type(b)
        end)
        if is_arr then
            local parts = {}
            for _, k in ipairs(keys) do table.insert(parts, encode_json(val[k], indent + 2)) end
            return "[\n" .. pad2 .. table.concat(parts, ",\n" .. pad2) .. "\n" .. pad .. "]"
        else
            local parts = {}
            for _, k in ipairs(keys) do
                local v = encode_json(val[k], indent + 2)
                table.insert(parts, '"' .. tostring(k) .. '": ' .. v)
            end
            return "{\n" .. pad2 .. table.concat(parts, ",\n" .. pad2) .. "\n" .. pad .. "}"
        end
    end
    return '"' .. tostring(val) .. '"'
end

local function write_json(subdir, filename, data)
    ensure_dir(DATA_BASE .. "/" .. subdir)
    return write_file(DATA_BASE .. "/" .. subdir .. "/" .. filename, encode_json(data))
end

local function read_json_field(content, key)
    if not content then return nil end
    local pat = '"' .. key .. '"%s*:%s*"([^"]*)"'
    local m = content:match(pat)
    if m then return m end
    local num = content:match('"' .. key .. '"%s*:%s*([%d%.%-]+)')
    if num then return tonumber(num) end
    local bool = content:match('"' .. key .. '"%s*:%s*(true|false)')
    if bool then return bool == "true" end
    return nil
end

local function object_from_json(content)
    if not content or content == "" then return nil end
    local obj = {}
    for k, v in content:gmatch('"([^"]+)"%s*:%s*"([^"]*)"') do obj[k] = v end
    for k, v in content:gmatch('"([^"]+)"%s*:%s*([%d%.%-]+)') do obj[k] = tonumber(v) end
    return next(obj) and obj or nil
end

local function read_json(subdir, filename)
    local content = read_file(DATA_BASE .. "/" .. subdir .. "/" .. filename)
    return object_from_json(content)
end

-- Screen-sharing detection
local sharing_cache = { value = false, time = 0 }

local function is_streaming()
    local now = os.time()
    if now - sharing_cache.time < 30 then return sharing_cache.value end
    sharing_cache.time = now
    local checks = {
        'pw-dump 2>/dev/null | grep -q \'"media.class".*"Stream/[A-Za-z]*/Video"\' && echo 1',
        'pw-link -l 2>/dev/null | grep -qiE "video|screen|cast|capture" && echo 1',
        'pw-cli ls Node 2>/dev/null | grep -B2 -A2 "Video" | grep -qiE "Stream|Capture|screen|cast" && echo 1',
    }
    for _, cmd in ipairs(checks) do
        local r = run(cmd .. " || echo 0")
        if r:match("1") then sharing_cache.value = true; return true end
    end
    sharing_cache.value = false
    return false
end

-- Fetch external IP info
local function fetch_ipinfo()
    local now = os.time()
    if now - last_fetch.ipinfo < TTL.ipinfo then return end
    last_fetch.ipinfo = now

    local isp = run(CURL .. ' -s --max-time 5 ipinfo.io/org 2>/dev/null')
    isp = isp:gsub("^%s+", ""):gsub("%s+$", ""):gsub("\n", "")
    isp = isp:gsub("^[Aa][Ss]%d+%s+", ""):gsub("^%u+%d+%s+", "")

    local tz = run(CURL .. ' -s --max-time 5 ipinfo.io/timezone 2>/dev/null')
    tz = tz:gsub("^%s+", ""):gsub("%s+$", ""):gsub("\n", "")

    local ip = run(CURL .. ' -s --max-time 5 ipinfo.io/ip 2>/dev/null')
    ip = ip:gsub("^%s+", ""):gsub("%s+$", ""):gsub("\n", "")

    write_json("network", "external.json", {
        isp = isp ~= "" and isp or "N/A",
        timezone = tz ~= "" and tz or "N/A",
        public_ip = ip ~= "" and ip or "N/A",
    })
end

-- Fetch latency
local function fetch_ping()
    local now = os.time()
    if now - last_fetch.ping < TTL.ping then return end
    last_fetch.ping = now

    local ping1 = run('/usr/bin/ping -c 3 -q 1.1.1.1 2>/dev/null')
    local loss = tonumber(string.match(ping1 or "", "([0-9]+)%% packet loss")) or 0
    local mdev = string.match(ping1 or "", "rtt [^=]+= [^/]+/[^/]+/[^/]+/([0-9.]+)")

    local ping2 = run('/usr/bin/ping -c 5 8.8.8.8 2>/dev/null')
    local avg = string.match(ping2 or "", "rtt [^=]+= [^/]+/([^/]+)/")
    local lat_mdev = string.match(ping2 or "", "rtt [^=]+= [^/]+/[^/]+/[^/]+/([0-9.]+)")

    local latency = "N/A"
    if avg then latency = avg .. "ms \u{00b1} " .. (lat_mdev or "0") .. "ms" end

    write_json("network", "latency.json", {
        loss = tostring(loss),
        jitter = string.format("%.2f", tonumber(mdev) or 0),
        latency = latency,
    })
end

-- Called by data.lua's conky_update_data() each cycle
function conky_update_ipinfo()
    fetch_ipinfo()
    fetch_ping()
end

-- Getters

function conky_isp()
    local d = read_json("network", "external.json")
    return d and d.isp or "N/A"
end

function conky_timezone()
    local d = read_json("network", "external.json")
    return d and d.timezone or "N/A"
end

function conky_public_ip()
    if is_streaming() then return "***.***.***.*** (Casting detected!)" end
    local d = read_json("network", "external.json")
    return d and d.public_ip or "N/A"
end

function conky_loss()
    local d = read_json("network", "latency.json")
    return d and d.loss or "0"
end

function conky_jitter()
    local d = read_json("network", "latency.json")
    return d and d.jitter or "0.00"
end

function conky_latency()
    local d = read_json("network", "latency.json")
    return d and d.latency or "N/A"
end

function conky_latency_target()
    return "8.8.8.8"
end

-- Initial fetch on load
conky_update_ipinfo()
