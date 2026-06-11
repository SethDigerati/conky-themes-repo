local script_dir = debug.getinfo(1, "S").source:match("^@(.*/)")
if not script_dir then script_dir = "" end

local DATA_BASE = "/tmp/conky"
local CURL = "/usr/bin/curl --max-time 10"
local API_KEY = ""
local NEWS_TTL = 3000

local last_fetch = {}
local TOPICS = {
    tech = { endpoint = "top-headlines", category = "technology" },
    science = { endpoint = "top-headlines", category = "science" },
    space = { endpoint = "everything", q = "space" },
    weather = { endpoint = "everything", q = "climate" },
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

local function fetch_topic(topic_key)
    local topic = TOPICS[topic_key]
    if not topic or API_KEY == "" then return end

    local now = os.time()
    if last_fetch[topic_key] and (now - last_fetch[topic_key]) < NEWS_TTL then
        return
    end

    ensure_dir(DATA_BASE .. "/news")

    local url
    if topic.endpoint == "everything" then
        url = "https://newsapi.org/v2/everything?q=" .. topic.q
            .. "&language=en&pageSize=5&apiKey=" .. API_KEY
    else
        url = "https://newsapi.org/v2/top-headlines?language=en&pageSize=2&apiKey=" .. API_KEY
        if topic.category then
            url = url .. "&category=" .. topic.category
        end
        if topic.q then
            url = url .. "&q=" .. topic.q
        end
    end

    local outfile = DATA_BASE .. "/news/" .. topic_key .. ".json"
    local tmpfile = outfile .. ".tmp"
    local cmd = CURL .. ' -s "' .. url .. '"'

    os.execute(cmd .. ' > "' .. tmpfile .. '" 2>/dev/null && mv "' .. tmpfile .. '" "' .. outfile .. '" &')

    last_fetch[topic_key] = now
end

local function parse_articles(topic_key)
    local content = read_file(DATA_BASE .. "/news/" .. topic_key .. ".json")
    if not content or content == "" then return nil end

    local articles_start = content:find('"articles"%s*:%s*%[')
    if not articles_start then return nil end

    local section = content:sub(articles_start):gsub("%s+", " ")
    local articles, pos = {}, 1

    while #articles < 2 do
        local obj_start = section:find('{', pos)
        if not obj_start then break end

        local depth, i = 1, obj_start + 1
        while depth > 0 and i <= #section do
            local c = section:sub(i, i)
            if c == '{' then depth = depth + 1
            elseif c == '}' then depth = depth - 1
            end
            i = i + 1
        end
        if depth ~= 0 then break end

        local obj = section:sub(obj_start, i - 1)
        pos = i

        local source = obj:match('"source"%s*:%s*{[^}]*"name"%s*:%s*"([^"]*)"') or ""
        local description = extract_json_str(obj, "description") or ""
        local pub_date = extract_json_str(obj, "publishedAt") or ""

        if description ~= "" then
            local date_str, time_str = "", ""
            if pub_date then
                local y, m, d, h, mi = pub_date:match("(%d%d%d%d)-(%d%d)-(%d%d)T(%d%d):(%d%d)")
                if y then
                    date_str = string.format("%s.%s.%s", d, m, y:sub(3, 4))
                    time_str = string.format("%s%s", h, mi)
                end
            end

            table.insert(articles, {
                title = description,
                source = source,
                country = "",
                date = date_str,
                time = time_str,
            })
        end
    end

    if #articles == 0 then return nil end
    return articles
end

local function word_wrap(text, max)
    if #text <= max then return text end
    local lines = {}
    while #text > max do
        local pos = text:sub(1, max):match("^.+%s()")
        if pos then
            local next_line = text:sub(pos)
            if #next_line > 0 and #next_line < 4 then
                table.insert(lines, text:sub(1, pos - 2) .. " " .. next_line)
                text = ""
                break
            end
            table.insert(lines, text:sub(1, pos - 2))
            text = next_line
        else
            table.insert(lines, text:sub(1, max))
            text = text:sub(max + 1)
        end
    end
    if #text > 0 then table.insert(lines, text) end
    return table.concat(lines, "\n")
end

local function load_topic(topic_key)
    local articles = parse_articles(topic_key)
    if not articles then return end

    for i = 1, 2 do
        if articles[i] then
            _G["news_" .. topic_key .. "_" .. i .. "_title"]   = word_wrap(articles[i].title or "", 55)
            _G["news_" .. topic_key .. "_" .. i .. "_source"]  = articles[i].source or ""
            _G["news_" .. topic_key .. "_" .. i .. "_country"] = ""
            _G["news_" .. topic_key .. "_" .. i .. "_date"]    = articles[i].date or ""
            _G["news_" .. topic_key .. "_" .. i .. "_time"]    = articles[i].time or ""
        end
    end
end

local fetch_order = { "tech", "science", "space", "weather" }
local fetch_index = 1

for _, topic in ipairs(fetch_order) do
    for art = 1, 2 do
        _G["news_" .. topic .. "_" .. art .. "_title"]   = ""
        _G["news_" .. topic .. "_" .. art .. "_source"]  = ""
        _G["news_" .. topic .. "_" .. art .. "_country"] = ""
        _G["news_" .. topic .. "_" .. art .. "_date"]    = ""
        _G["news_" .. topic .. "_" .. art .. "_time"]    = ""
    end
end

function conky_update_news()
    if API_KEY == "" then return end
    fetch_topic(fetch_order[fetch_index])
    fetch_index = fetch_index + 1
    if fetch_index > #fetch_order then fetch_index = 1 end
    for _, topic in ipairs(fetch_order) do
        load_topic(topic)
    end
end

function conky_news_source() return "SOURCE: NewsAPI.org" end

local field_names = { "title", "source", "country", "date", "time" }
for _, topic in ipairs(fetch_order) do
    for art = 1, 2 do
        for _, fname in ipairs(field_names) do
            local g = "news_" .. topic .. "_" .. art .. "_" .. fname
            _G["conky_news_" .. topic .. "_" .. art .. "_" .. fname] = function()
                return _G[g]
            end
        end
    end
end
