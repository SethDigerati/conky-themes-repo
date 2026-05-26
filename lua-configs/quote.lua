-- Quote fetcher for Conky
-- Fetches daily quote from ZenQuotes API, caches to /tmp/conky/quote/

local DATA_BASE = "/tmp/conky"
local CURL = "/usr/bin/curl"

local TTL = { quote = 86400 }
local last_fetch = { quote = 0 }

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

-- Word-wrap helpers
local function wrap_paragraph(par, width)
    local parts = {}
    local cur = ""
    for word in par:gmatch("%S+") do
        local wlen = #word
        if cur == "" then
            if wlen > width then
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
    width = tonumber(width) or 40
    local out = {}
    for line in (text .. "\n"):gmatch("(.-)\n") do
        table.insert(out, wrap_paragraph(line, width))
    end
    return table.concat(out, "\n")
end

-- Fetch quote from ZenQuotes
local function fetch_quote()
    local now = os.time()
    if now - last_fetch.quote < TTL.quote then return end
    last_fetch.quote = now

    local env_key = os.getenv("ZENQUOTES_API_KEY")
    local url = "https://zenquotes.io/api/today"
    if env_key and env_key ~= "" then
        url = url .. "?token=" .. env_key
    end

    local raw = run(CURL .. ' -s -S --connect-timeout 5 --max-time 10 "' .. url .. '" 2>/dev/null')
    if not raw or raw == "" then return end

    ensure_dir(DATA_BASE .. "/quote")
    write_file(DATA_BASE .. "/quote/raw.json", raw)

    -- Download author image
    local q = raw:match('"q"%s*:%s*"(.-)"')
    local a = raw:match('"a"%s*:%s*"(.-)"')
    local i = raw:match('"i"%s*:%s*"(.-)"')

    if q then
        local img_url = i or ""
        if img_url ~= "" then
            run(CURL .. ' -s -S --connect-timeout 5 --max-time 10 -o "' .. DATA_BASE .. '/quote/author.png"' .. ' "' .. img_url .. '" 2>/dev/null')
        end
        -- Fallback avatar
        local author_file = DATA_BASE .. "/quote/author.png"
        local f_img = io.open(author_file, "r")
        if not f_img and a then
            local safe = a:gsub("([^%w%-%_%.%~ ])", function(c) return string.format("%%%02X", string.byte(c)) end):gsub(" ", "+")
            run(CURL .. ' -s -S --connect-timeout 5 --max-time 10 -o "' .. author_file .. '"' .. ' "https://ui-avatars.com/api/?name=' .. safe .. '&size=256&background=000000&color=ffffff&format=png" 2>/dev/null')
        elseif f_img then
            f_img:close()
        end
    end
end

-- Getters

function conky_quote()
    local content = read_file(DATA_BASE .. "/quote/raw.json")
    if not content then return "" end
    local q = content:match('"q"%s*:%s*"(.-)"') or content:match('"quote"%s*:%s*"(.-)"')
    if not q then return "" end
    q = q:gsub('\\"', '"'):gsub('\\n', '\n')
    return wrap_text(q, 40)
end

function conky_quote_author()
    local content = read_file(DATA_BASE .. "/quote/raw.json")
    if not content then return "" end
    local a = content:match('"a"%s*:%s*"(.-)"') or content:match('"author"%s*:%s*"(.-)"')
    return a or ""
end

function conky_quote_author_image()
    local path = DATA_BASE .. "/quote/author.png"
    local f = io.open(path, "r")
    if f then f:close(); return path end
    return ""
end

function conky_quote_update_time()
    return os.date("%Y-%m-%d %H:%M:%S", last_fetch.quote)
end

-- Initial fetch on load
fetch_quote()
