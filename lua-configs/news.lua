local script_dir = debug.getinfo(1, "S").source:match("^@(.*/)")
if not script_dir then script_dir = "" end

local DATA_BASE = "/tmp/conky"
local CURL = "/usr/bin/curl"
local API_KEY = ""
local NEWS_TTL = 3000

local last_fetch = {}
local TOPICS = {
    tech = "technology",
    science = "science",
    space = "space",
    politics = "politics",
    entertainment = "entertainment",
    finance = "finance",
    weather = "environment",
    sports = "sports",
    f1 = "motor sports",
}

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
    return s:gsub("^%s+", ""):gsub("%s+$", "")
end

local function read_env(target_key)
    local env_path = script_dir .. "../.env"
    local f = io.open(env_path, "r")
    if not f then return nil end
    for raw_line in f:lines() do
        local l = raw_line:gsub("#.*$", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if l ~= "" then
            local k, v = l:match("^([^=]+)=(.+)$")
            if k and k == target_key then
                v = v:gsub('^"', ''):gsub('"$', ''):gsub("^'", ''):gsub("'$", '')
                f:close()
                return v
            end
        end
    end
    f:close()
    return nil
end

API_KEY = read_env("NEWS_API_KEY") or os.getenv("NEWS_API_KEY") or ""

local function extract_json_str(content, key)
    local pat = '"' .. key .. '"%s*:%s*"([^"]*)"'
    return content:match(pat)
end

local function extract_json_arr_first(content, key)
    local pat = '"' .. key .. '"%s*:%s*%[%s*"([^"]*)"'
    return content:match(pat)
end

local function fetch_topic(topic_key)
    local topic = TOPICS[topic_key]
    if not topic or API_KEY == "" then return end

    local now = os.time()
    if last_fetch[topic_key] and (now - last_fetch[topic_key]) < NEWS_TTL then
        return
    end

    ensure_dir(DATA_BASE .. "/news")

    local url = "https://api.freenewsapi.io/v1/news?topic="
        .. topic:gsub(" ", "%%20")
        .. "&language=en"

    local cmd = CURL .. ' -s -H "x-api-key: ' .. API_KEY .. '" "' .. url .. '"'
    local response = run(cmd)

    if response and response ~= "" and response:sub(1, 1) == "{" then
        write_file(DATA_BASE .. "/news/" .. topic_key .. ".json", response)
        last_fetch[topic_key] = now
    end
end

local function format_article(source, title, country, pub_date)
    if #source > 12 then
        source = source:sub(1, 10) .. ".."
    end

    if #title > 55 then
        title = title:sub(1, 52) .. "..."
    end

    local date_str = ""
    if pub_date then
        local y, m, d, h, mi = pub_date:match("(%d%d%d%d)-(%d%d)-(%d%d)T(%d%d):(%d%d)")
        if y then
            date_str = string.format("%s.%s.%s, %s;%s", d, m, y:sub(3, 4), h, mi)
        end
    end

    local line1 = "${color1}[" .. source .. "] ${color0}" .. title
    local meta_parts = {}
    if country and country ~= "" then
        table.insert(meta_parts, "◎ " .. country)
    end
    if date_str ~= "" then
        table.insert(meta_parts, "• " .. date_str)
    end
    local line2 = "${alignr}" .. table.concat(meta_parts, "  ")

    return line1 .. "\n" .. line2
end

local function get_news_block(topic_key)
    local content = read_file(DATA_BASE .. "/news/" .. topic_key .. ".json")
    if not content or content == "" then
        if API_KEY == "" then
            return "${color3}Configure NEWS_API_KEY in .env${color}"
        end
        return ""
    end

    local data_start = content:find('"data"%s*:%s*%[')
    if not data_start then
        return "${color3}No news${color}"
    end

    local data_section = content:sub(data_start)
    local lines, count, pos = {}, 0, 1

    while count < 2 do
        local s, e = data_section:find('{.-}', pos)
        if not s then break end

        local obj = data_section:sub(s, e)
        pos = e + 1

        if obj:find('"uuid"') then
            local title = extract_json_str(obj, "title") or ""
            local source = extract_json_str(obj, "publisher") or ""
            local country = extract_json_arr_first(obj, "countries") or ""
            local pub_date = extract_json_str(obj, "published_at") or ""

            if title ~= "" then
                table.insert(lines, format_article(source, title, country, pub_date))
                count = count + 1
            end
        end
    end

    if #lines == 0 then
        return "${color3}No news${color}"
    end

    return table.concat(lines, "\n")
end

function conky_update_news()
    if API_KEY == "" then return end
    for k in pairs(TOPICS) do
        fetch_topic(k)
    end
end

function conky_news_tech() return get_news_block("tech") end
function conky_news_science() return get_news_block("science") end
function conky_news_space() return get_news_block("space") end
function conky_news_politics() return get_news_block("politics") end
function conky_news_entertainment() return get_news_block("entertainment") end
function conky_news_finance() return get_news_block("finance") end
function conky_news_weather() return get_news_block("weather") end
function conky_news_sports() return get_news_block("sports") end
function conky_news_f1() return get_news_block("f1") end
