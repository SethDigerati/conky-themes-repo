#!/usr/bin/env lua
-- Simple background daemon for Conky network stats (Lua)
-- Saves results in $XDG_RUNTIME_DIR/netstats/netstats.json

local TARGET = "1.1.1.1"
local XDG_RUNTIME_DIR = os.getenv("XDG_RUNTIME_DIR") or "/tmp"
local TMPDIR = XDG_RUNTIME_DIR .. "/netstats"
local TMPFILE = TMPDIR .. "/netstats.json"
local LOGFILE = "/tmp/netstats.log"

local function run(cmd)
    local f = io.popen(cmd)
    if not f then return "" end
    local s = f:read("*a")
    f:close()
    return s
end

local function log(msg)
    local f = io.open(LOGFILE, "a")
    if f then
        f:write(string.format("[netstats] %s %s\n", os.date("%F %T"), msg))
        f:close()
    end
end

local function ensure_file_exists(filepath)
    local f = io.open(filepath, "r")
    if f then
        f:close()
        return true
    else
        -- Create empty JSON with default values
        f = io.open(filepath, "w")
        if f then
            f:write('{"jitter": 0.000, "loss": 0}\n')
            f:close()
            return true
        end
        return false
    end
end

-- ensure cache dir exists
os.execute('mkdir -p "' .. TMPDIR .. '" 2>/dev/null')

-- ensure JSON file exists
ensure_file_exists(TMPFILE)

-- avoid duplicate daemons (count matching "netstats" processes)
do
    local pids = run('pgrep -f "netstats" 2>/dev/null')
    local count = 0
    for _ in string.gmatch(pids, "%S+") do count = count + 1 end
    if count > 1 then
        log("Already running.")
        os.exit(0)
    end
end

math.randomseed(os.time() + (tonumber(run("echo $$")) or 0))

local function update_stats()
    log("Updating stats...")
    -- run ping (10 packets) and capture output
    local ping_cmd = '/usr/bin/ping -c 10 -q "' .. TARGET .. '" 2>/dev/null'
    local ping_output = run(ping_cmd)

    -- extract packet loss (percentage)
    local loss = tonumber(string.match(ping_output or "", "([0-9]+)%% packet loss")) or 0

    -- jitter: random 0..5 (replicates original awk rand()*5)
    local jitter = math.random() * 5

    -- ensure file exists before writing
    ensure_file_exists(TMPFILE)

    -- write JSON
    local f = io.open(TMPFILE, "w")
    if f then
        f:write(string.format('{"jitter": %.3f, "loss": %d}\n', jitter, loss))
        f:close()
    else
        log("Failed to write " .. TMPFILE)
    end

    -- log current stats
    local stats = run('cat "' .. TMPFILE .. '" 2>/dev/null')
    log("Stats updated: " .. (stats:gsub("\n", "") or ""))
end

-- main loop
log("Daemon started at " .. os.date("%c"))
while true do
    update_stats()
    os.execute("sleep 300")
end
