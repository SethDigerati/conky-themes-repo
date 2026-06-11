local script_dir = debug.getinfo(1, "S").source:match("^@(.*/)")
if not script_dir then script_dir = "" end

local DATA_BASE = "/tmp/conky"
local CURL = "/usr/bin/curl --max-time 8"
local API_KEY = ""
local NEWS_TTL = 3000

local last_fetch = {}
local news_cache = {}
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

local function read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local c = f:read("*a")
    f:close()
    return c
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

    local outfile = DATA_BASE .. "/news/" .. topic_key .. ".json"
    local tmpfile = outfile .. ".tmp"
    local cmd = CURL .. ' -s -H "x-api-key: ' .. API_KEY .. '" "' .. url .. '"'

    os.execute(cmd .. ' > "' .. tmpfile .. '" 2>/dev/null && mv "' .. tmpfile .. '" "' .. outfile .. '" &')

    last_fetch[topic_key] = now
    news_cache[topic_key] = nil
end

local function parse_articles(topic_key)
    local content = read_file(DATA_BASE .. "/news/" .. topic_key .. ".json")
    if not content or content == "" then
        news_cache[topic_key] = {}
        return
    end

    local data_start = content:find('"data"%s*:%s*%[')
    if not data_start then
        news_cache[topic_key] = {}
        return
    end

    local data_section = content:sub(data_start)
    local articles, pos = {}, 1

    while #articles < 2 do
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
                if #source > 12 then
                    source = source:sub(1, 10) .. ".."
                end
                if #title > 55 then
                    title = title:sub(1, 52) .. "..."
                end

                local date_str, time_str = "", ""
                if pub_date then
                    local y, m, d, h, mi = pub_date:match("(%d%d%d%d)-(%d%d)-(%d%d)T(%d%d):(%d%d)")
                    if y then
                        date_str = string.format("%s.%s.%s", d, m, y:sub(3, 4))
                        time_str = string.format("%s;%s", h, mi)
                    end
                end

                table.insert(articles, {
                    title = title,
                    source = source,
                    country = country,
                    date = date_str,
                    time = time_str,
                })
            end
        end
    end

    news_cache[topic_key] = articles
end

local function get_news_field(topic_key, article_num, field)
    if not news_cache[topic_key] then
        parse_articles(topic_key)
    end
    if not news_cache[topic_key] or #news_cache[topic_key] < article_num then
        return ""
    end
    local val = news_cache[topic_key][article_num][field]
    return val or ""
end

local fetch_order = { "tech", "science", "space", "politics", "entertainment", "finance", "weather", "sports", "f1" }
local fetch_index = 1

function conky_update_news()
    if API_KEY == "" then return end
    for _ = 1, 3 do
        fetch_topic(fetch_order[fetch_index])
        fetch_index = fetch_index + 1
        if fetch_index > #fetch_order then fetch_index = 1 end
    end
end

function conky_news_source() return "SOURCE: FreeNewsApi.io" end

local field_names = { "title", "source", "country", "date", "time" }
for _, topic in ipairs(fetch_order) do
    for art = 1, 2 do
        for _, fname in ipairs(field_names) do
            local t, a, f = topic, art, fname
            _G["conky_news_" .. topic .. "_" .. art .. "_" .. fname] = function()
                return get_news_field(t, a, f)
            end
        end
    end
end
