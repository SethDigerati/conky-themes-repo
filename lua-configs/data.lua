-- Central data watcher for all Conky widgets
-- Watches /proc/, /sys/, and /tmp/conky/ cached files
-- Writes all data to /tmp/conky/{category}/ for widget scripts to consume

local script_dir = debug.getinfo(1, "S").source:match("^@(.*/)")

local DATA_BASE = "/tmp/conky"

-- TTL for each data source (seconds, 0 = every cycle)
local TTL = { static = 86400 }
local last_fetch = { static = 0 }

-- ============================================================
-- HELPERS
-- ============================================================

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

-- ============================================================
-- MINIMAL JSON WRITER
-- ============================================================

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
        for k in pairs(val) do
            table.insert(keys, k)
            if type(k) ~= "number" then is_arr = false end
        end
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

-- ============================================================
-- JSON READER (regex-based, lightweight)
-- ============================================================

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

-- ============================================================
-- SYSTEM DATA COLLECTION (from /proc/ and /sys/)
-- ============================================================

local static_cache = {}

local function read_sys(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local v = f:read("*l")
    f:close()
    return v
end

local function collect_cpu()
    local load = read_file("/proc/loadavg")
    local l1, l5, l15, procs = load:match("([%d%.]+) ([%d%.]+) ([%d%.]+) ([%d]+/%d+)")
    write_json("system", "cpu.json", {
        load1 = l1 or "0",
        load5 = l5 or "0",
        load15 = l15 or "0",
        procs = procs or "0/0",
    })
end

local function collect_memory()
    local data = {}
    local f = io.open("/proc/meminfo")
    if f then
        for line in f:lines() do
            local k, v = line:match("^(%w+):%s+(%d+)")
            if k then data[k] = tonumber(v) end
        end
        f:close()
    end
    write_json("system", "memory.json", data)
end

local function collect_temps()
    local temps = {}
    local hwmon_ls = io.popen("ls /sys/class/hwmon/ 2>/dev/null")
    if hwmon_ls then
        for entry in hwmon_ls:lines() do
            local name = read_sys("/sys/class/hwmon/" .. entry .. "/name") or "unknown"
            local i = 1
            while true do
                local raw = read_sys("/sys/class/hwmon/" .. entry .. "/temp" .. i .. "_input")
                if not raw then break end
                local label = read_sys("/sys/class/hwmon/" .. entry .. "/temp" .. i .. "_label") or ("Sensor " .. i)
                table.insert(temps, {
                    sensor = entry,
                    name = name:gsub("%s+$", ""),
                    label = label:gsub("%s+$", ""),
                    temp_c = math.floor((tonumber(raw) or 0) / 10) / 100,
                })
                i = i + 1
            end
        end
        hwmon_ls:close()
    end
    write_json("system", "temps.json", temps)
end

local function collect_battery()
    local bat = {}
    local base = "/sys/class/power_supply/BAT0"
    -- Try energy_* (µWh) first, fall back to charge_* (µAh) for older batteries
    local pairs = {
        {"energy_now", "charge_now"},
        {"energy_full", "charge_full"},
        {"energy_full_design", "charge_full_design"},
    }
    for _, pair in ipairs(pairs) do
        local val = read_sys(base .. "/" .. pair[1]) or read_sys(base .. "/" .. pair[2])
        if val then bat[pair[1]] = val:gsub("%s+$", "") end
    end
    for _, f in ipairs({"power_now", "status", "technology"}) do
        local val = read_sys(base .. "/" .. f)
        if val then bat[f] = val:gsub("%s+$", "") end
    end
    write_json("system", "battery.json", bat)
end

local function collect_gpu()
    local cur = read_sys("/sys/class/drm/card0/gt_cur_freq_mhz") or ""
    local max = read_sys("/sys/class/drm/card0/gt_max_freq_mhz") or ""
    local shmem = 0
    local meminfo = read_file("/proc/meminfo")
    if meminfo then
        shmem = tonumber(meminfo:match("Shmem:%s+(%d+)")) or 0
    end
    write_json("system", "gpu.json", {
        freq_cur = cur:gsub("%s+$", ""),
        freq_max = max:gsub("%s+$", ""),
        mem_used = math.floor(shmem / 1024),
    })
end

local function collect_static()
    if os.time() - last_fetch.static < TTL.static and next(static_cache) then return end
    last_fetch.static = os.time()

    local model = run("lspci 2>/dev/null | grep -i vga | cut -d: -f3 | sed 's/^ *//' | head -1"):gsub("%s+$", "")
    local driver = run("lsmod 2>/dev/null | grep -E '^i915|^xe' | awk '{print $1}' | head -1"):gsub("%s+$", "")
    local kernel = run("uname -r 2>/dev/null | cut -d'-' -f1"):gsub("%s+$", "")
    local mem_total = 0
    local meminfo = read_file("/proc/meminfo")
    if meminfo then mem_total = tonumber(meminfo:match("MemTotal:%s+(%d+)")) or 0 end

    -- Battery static info
    local bat_tech = read_sys("/sys/class/power_supply/BAT0/technology") or "N/A"
    local bat_design = read_sys("/sys/class/power_supply/BAT0/energy_full_design")
        or read_sys("/sys/class/power_supply/BAT0/charge_full_design") or "0"

    static_cache = {
        gpu_model = model ~= "" and model or "N/A",
        gpu_driver = driver ~= "" and driver or "N/A",
        kernel = kernel ~= "" and kernel or "N/A",
        mem_total = math.floor(mem_total / 1024),
        battery_tech = bat_tech:gsub("%s+$", ""),
        battery_design = bat_design:gsub("%s+$", ""),
    }
    write_json("system", "static.json", static_cache)
end

-- ============================================================
-- NETWORK DATA COLLECTION
-- ============================================================

local function collect_iface_stats()
    local data = {}
    local f = io.open("/proc/net/dev")
    if f then
        for line in f:lines() do
            local name, rx, tx = line:match("^%s*(%w+):%s+(%d+)%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+(%d+)")
            if name and name ~= "lo" then
                data[name] = { rx_bytes = tonumber(rx), tx_bytes = tonumber(tx) }
            end
        end
        f:close()
    end
    write_json("network", "iface.json", data)
end

-- ============================================================
-- STORAGE COLLECTION
-- ============================================================

local function collect_storage()
    local devices = run("lsblk -ro NAME,SIZE,TYPE,MOUNTPOINTS 2>/dev/null | awk '$3==\"disk\"||$3==\"rom\"{print \"─\"$1\"-------(\"$2\")\"}; $3==\"part\"{mnt=$4; if(length(mnt)>20) mnt=substr(mnt,1,17) \"...\"; print \"     └\"$1\"-----(\"$2\")_\" mnt}'")
    write_json("system", "storage.json", { devices = devices:gsub("%s+$", "") })
end

-- ============================================================
-- MAIN UPDATE (called via lua_draw_hook_post)
-- ============================================================

function conky_update_data()
    ensure_dir(DATA_BASE)

    -- System data: read every cycle from /proc/ and /sys/
    collect_cpu()
    collect_memory()
    collect_temps()
    collect_battery()
    collect_gpu()
    collect_static()

    -- Storage device list (rate-limited by execi-like interval via TTL)
    collect_storage()

    -- Network data from /proc/ every cycle
    collect_iface_stats()

    -- Call API updaters if their modules are loaded alongside this one
    if type(conky_update_ipinfo) == "function" then conky_update_ipinfo() end
end

-- ============================================================
-- GETTER FUNCTIONS FOR gpurc
-- ============================================================

function conky_gpu_model()
    return static_cache.gpu_model or "N/A"
end

function conky_gpu_driver()
    return static_cache.gpu_driver or "N/A"
end

function conky_gpu_mem_used()
    local d = read_json("system", "gpu.json")
    return d and d.mem_used or "0"
end

function conky_gpu_mem_total()
    return static_cache.mem_total or "0"
end

function conky_gpu_temp()
    local temps = read_file(DATA_BASE .. "/system/temps.json")
    if not temps then return "N/A" end
    for entry, line in temps:gmatch('"label"%s*:%s*"([^"]+)"[^}]+"temp_c"%s*:%s*([%d%.]+)') do
        local el = entry:lower()
        if el:find("gpu") or el:find("amdgpu") or el:find("i915") then return line end
    end
    for entry, line in temps:gmatch('"name"%s*:%s*"([^"]+)"[^}]+"temp_c"%s*:%s*([%d%.]+)') do
        local el = entry:lower()
        if el:find("amdgpu") or el:find("i915") or el:find("nouveau") or el:find("nvidia") then return line end
    end
    -- Fallback: first die sensor
    local die = temps:match('"temp_c"%s*:%s*([%d%.]+)')
    return die or "N/A"
end

function conky_gpu_freq_cur()
    local d = read_json("system", "gpu.json")
    return d and d.freq_cur or "N/A"
end

function conky_gpu_freq_max()
    local d = read_json("system", "gpu.json")
    return d and d.freq_max or "N/A"
end

function conky_kernel()
    return static_cache.kernel or "N/A"
end

-- ============================================================
-- GETTER FUNCTIONS FOR systemrc
-- ============================================================

function conky_battery_tech()
    return static_cache.battery_tech or "N/A"
end

function conky_battery_energy_full_design()
    local d = read_json("system", "battery.json")
    local val = d and d.energy_full_design or static_cache.battery_design
    if not val or val == "N/A" or val == "0" then return "N/A" end
    return string.format("%.2f", tonumber(val) / 1000000)
end

function conky_battery_energy()
    local d = read_json("system", "battery.json")
    if not d then return "N/A" end
    local val = d.energy_now
    if not val then return "N/A" end
    return string.format("%.2f", tonumber(val) / 1000000)
end

function conky_battery_energy_full()
    local d = read_json("system", "battery.json")
    if not d or not d.energy_full then return "N/A" end
    return string.format("%.2f", tonumber(d.energy_full) / 1000000)
end

-- ============================================================
-- GETTER FUNCTIONS FOR networkrc (additional)
-- ============================================================

function conky_network_temp()
    local temps = read_file(DATA_BASE .. "/system/temps.json")
    if not temps then return "N/A" end
    for label, temp in temps:gmatch('"label"%s*:%s*"([^"]+)"[^}]+"temp_c"%s*:%s*([%d%.]+)') do
        local l = label:lower()
        if l:find("wifi") or l:find("wl") or l:find("network") or l:find("enp") or l:find("eth") or l:find("mac") then
            return temp
        end
    end
    for name, temp in temps:gmatch('"name"%s*:%s*"([^"]+)"[^}]+"temp_c"%s*:%s*([%d%.]+)') do
        local n = name:lower()
        if n:find("wifi") or n:find("net") or n:find("wireless") or n:find("iwl") then
            return temp
        end
    end
    return "N/A"
end

-- ============================================================
-- GETTER FUNCTIONS FOR memoryrc
-- ============================================================

function conky_storage_devices()
    local d = read_json("system", "storage.json")
    return d and d.devices or ""
end

function conky_storage_temp()
    local temps = read_file(DATA_BASE .. "/system/temps.json")
    if not temps then return "N/A" end
    for entry, label, temp in temps:gmatch('"sensor"%s*:%s*"([^"]+)"[^}]+"label"%s*:%s*"([^"]+)"[^}]+"temp_c"%s*:%s*([%d%.]+)') do
        local l = label:lower()
        if l:find("nvme") or l:find("ahci") or l:find("storage") or l:find("sata") or l:find("disk") then
            return temp
        end
    end
    return "N/A"
end
