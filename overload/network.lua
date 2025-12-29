-- Network stats Lua module for Conky
-- Fetches and caches data in $XDG_RUNTIME_DIR/netstats/

local XDG_RUNTIME_DIR = os.getenv("XDG_RUNTIME_DIR") or "/tmp"
local TMPDIR = XDG_RUNTIME_DIR .. "/netstats"
local TMPFILE = TMPDIR .. "/netstats.json"
local TMPFILE_TMP = TMPFILE .. ".tmp"
local CURL = "/usr/bin/curl"

local PING_TARGET = "1.1.1.1"
local LATENCY_TARGET = "8.8.8.8"

-- Update intervals (seconds)
local PING_INTERVAL = 15
local IPINFO_INTERVAL = 600

-- Timestamps for throttling
local last_ping_time = 0
local last_ipinfo_time = 0

-- Create cache dir
os.execute('mkdir -p "' .. TMPDIR .. '" 2>/dev/null')

local function run(cmd)
    local f = io.popen(cmd)
    if not f then return "" end
    local s = f:read("*a")
    f:close()
    return s
end

local function escape_json(str)
    if not str then return "" end
    return str:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t')
end

-- Cached display data
local display_data = {
    loss = "0",
    jitter = "0.00",
    latency = "N/A",
    isp = "N/A",
    timezone = "N/A",
    public_ip = "N/A"
}

local function write_json()
    local f = io.open(TMPFILE_TMP, "w")
    if f then
        f:write('{\n')
        f:write(string.format('  "loss": "%s",\n', escape_json(display_data.loss)))
        f:write(string.format('  "jitter": "%s",\n', escape_json(display_data.jitter)))
        f:write(string.format('  "latency": "%s",\n', escape_json(display_data.latency)))
        f:write(string.format('  "isp": "%s",\n', escape_json(display_data.isp)))
        f:write(string.format('  "timezone": "%s",\n', escape_json(display_data.timezone)))
        f:write(string.format('  "public_ip": "%s",\n', escape_json(display_data.public_ip)))
        f:write(string.format('  "updated": "%s"\n', os.date("%Y-%m-%d %H:%M:%S")))
        f:write('}\n')
        f:close()
        os.execute('mv "' .. TMPFILE_TMP .. '" "' .. TMPFILE .. '"')
    end
end

local function read_cached_json()
    local f = io.open(TMPFILE, "r")
    if not f then return false end
    local content = f:read("*a")
    f:close()
    
    if not content or content == "" then return false end
    
    display_data.loss = content:match('"loss":%s*"([^"]*)"') or display_data.loss
    display_data.jitter = content:match('"jitter":%s*"([^"]*)"') or display_data.jitter
    display_data.latency = content:match('"latency":%s*"([^"]*)"') or display_data.latency
    display_data.isp = content:match('"isp":%s*"([^"]*)"') or display_data.isp
    display_data.timezone = content:match('"timezone":%s*"([^"]*)"') or display_data.timezone
    display_data.public_ip = content:match('"public_ip":%s*"([^"]*)"') or display_data.public_ip
    return true
end

local function fetch_ipinfo()
    -- Get ISP/org
    local isp = run(CURL .. ' -s --max-time 5 ipinfo.io/org 2>/dev/null')
    isp = isp:gsub("^%s+", ""):gsub("%s+$", ""):gsub("\n", "")
    -- Remove AS number prefix (e.g., "AS33771 Safaricom Limited" -> "Safaricom Limited")
    isp = isp:gsub("^[Aa][Ss]%d+%s+", "")
    isp = isp:gsub("^%u+%d+%s+", "")
    if isp and isp ~= "" then
        display_data.isp = isp
    end
    
    -- Get timezone
    local timezone = run(CURL .. ' -s --max-time 5 ipinfo.io/timezone 2>/dev/null')
    timezone = timezone:gsub("^%s+", ""):gsub("%s+$", ""):gsub("\n", "")
    if timezone and timezone ~= "" then
        display_data.timezone = timezone
    end
    
    -- Get public IP
    local public_ip = run(CURL .. ' -s --max-time 5 ipinfo.io/ip 2>/dev/null')
    public_ip = public_ip:gsub("^%s+", ""):gsub("%s+$", ""):gsub("\n", "")
    if public_ip and public_ip ~= "" then
        display_data.public_ip = public_ip
    end
end

local function fetch_ping_stats()
    -- Ping for loss and jitter (to 1.1.1.1)
    local ping_output = run('/usr/bin/ping -c 3 -q "' .. PING_TARGET .. '" 2>/dev/null')
    
    -- Extract packet loss
    local loss = tonumber(string.match(ping_output or "", "([0-9]+)%% packet loss")) or 0
    display_data.loss = tostring(loss)
    
    -- Extract jitter (mdev from rtt line)
    local mdev = string.match(ping_output or "", "rtt [^=]+= [^/]+/[^/]+/[^/]+/([0-9.]+)")
    display_data.jitter = string.format("%.2f", tonumber(mdev) or 0)
    
    -- Ping for latency (to 8.8.8.8)
    local latency_output = run('/usr/bin/ping -c 5 "' .. LATENCY_TARGET .. '" 2>/dev/null')
    
    -- Extract avg and mdev from rtt line
    local avg = string.match(latency_output or "", "rtt [^=]+= [^/]+/([^/]+)/")
    local lat_mdev = string.match(latency_output or "", "rtt [^=]+= [^/]+/[^/]+/[^/]+/([0-9.]+)")
    
    if avg then
        display_data.latency = avg .. " ms ± " .. (lat_mdev or "0") .. " ms"
    else
        display_data.latency = "N/A"
    end
end

-- Called by Conky draw hook
function conky_update_network()
    local now = os.time()
    
    -- Load cached data on first run
    if last_ping_time == 0 then
        read_cached_json()
    end
    
    -- Fetch ipinfo if interval elapsed
    if (now - last_ipinfo_time) >= IPINFO_INTERVAL then
        fetch_ipinfo()
        last_ipinfo_time = now
        write_json()
    end
    
    -- Fetch ping stats if interval elapsed
    if (now - last_ping_time) >= PING_INTERVAL then
        fetch_ping_stats()
        last_ping_time = now
        write_json()
    end
end

function conky_loss()
    return display_data.loss
end

function conky_jitter()
    return display_data.jitter
end

function conky_latency()
    return display_data.latency
end

function conky_isp()
    return display_data.isp
end

function conky_timezone()
    return display_data.timezone
end

function conky_public_ip()
    return display_data.public_ip
end
