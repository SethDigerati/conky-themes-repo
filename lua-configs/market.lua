-- Market Data Widget (CoinGecko + Open ER API)
-- Caches: /tmp/conky/market/

local DATA_BASE = "/tmp/conky/market"

local function read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local c = f:read("*a")
    f:close()
    return c
end

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

local function run(cmd)
    local f = io.popen(cmd)
    if not f then return "" end
    local s = f:read("*a")
    f:close()
    return s
end

local CURL = "/usr/bin/curl"

local assets = {
    { name = "BTC", cg_id = "bitcoin" },
    { name = "ETH", cg_id = "ethereum" },
    { name = "SOL", cg_id = "solana" },
    { name = "XRP", cg_id = "ripple" },
    { name = "DOGE", cg_id = "dogecoin" },
    { name = "ADA", cg_id = "cardano" },
    { name = "BNB", cg_id = "binancecoin" },
    { name = "TRX", cg_id = "tron" },
    { name = "AVAX", cg_id = "avalanche-2" },
    { name = "LINK", cg_id = "chainlink" },
    { name = "DOT", cg_id = "polkadot" },
    { name = "LTC", cg_id = "litecoin" },
}

local last_markets_fetch = 0
local last_forex_fetch = 0
local MARKETS_TTL = 240
local FOREX_TTL = 240

local location_cache = { country = "" }

local country_currency = {
    US = "USD", IN = "INR", GB = "GBP", JP = "JPY",
    DE = "EUR", FR = "EUR", IT = "EUR", ES = "EUR",
    NL = "EUR", BE = "EUR", PT = "EUR", IE = "EUR",
    AT = "EUR", FI = "EUR", GR = "EUR",
    CA = "CAD", AU = "AUD", CH = "CHF", CN = "CNY",
    KR = "KRW", SG = "SGD", HK = "HKD", TW = "TWD",
    BR = "BRL", MX = "MXN", ZA = "ZAR", SE = "SEK",
    NO = "NOK", NZ = "NZD", RU = "RUB", TR = "TRY",
    AE = "AED", SA = "SAR", TH = "THB", MY = "MYR",
    PH = "PHP", ID = "IDR", VN = "VND", EG = "EGP",
    AR = "ARS", CO = "COP", CL = "CLP", PE = "PEN",
    PL = "PLN", CZ = "CZK", HU = "HUF", DK = "DKK",
    IL = "ILS", PK = "PKR", BD = "BDT", NG = "NGN",
    KE = "KES", TZ = "TZS", UG = "UGX", GH = "GHS",
    MA = "MAD", DZ = "DZD", TN = "TND", QA = "QAR",
    KW = "KWD", OM = "OMR", BH = "BHD", JO = "JOD",
    LB = "LBP", RO = "RON", BG = "BGN", RS = "RSD",
    HR = "HRK", IS = "ISK", LT = "EUR", LV = "EUR",
    EE = "EUR", SK = "EUR", SI = "EUR", CY = "EUR",
    MT = "EUR", LU = "EUR",
}

local currency_symbols = {
    USD = "$", INR = "₹", EUR = "€", JPY = "¥",
    GBP = "£", CAD = "C$", AUD = "A$", CHF = "Fr",
    CNY = "¥", KRW = "₩", SGD = "S$", HKD = "HK$",
    TWD = "NT$", BRL = "R$", MXN = "MX$", ZAR = "R",
    SEK = "kr", NOK = "kr", NZD = "NZ$", RUB = "₽",
    TRY = "₺", AED = "د.إ", SAR = "﷼", THB = "฿",
    ILS = "₪", PLN = "zł", CZK = "Kč", HUF = "Ft",
    DKK = "kr",
}

ensure_dir(DATA_BASE)

-- ============ LOCATION ============
local function fetch_location()
    if location_cache.country ~= "" then return end
    local country = run(CURL .. ' -s --max-time 5 ipinfo.io/country 2>/dev/null')
        :gsub("^%s+", ""):gsub("%s+$", ""):gsub("\n", "")
    if country ~= "" then
        location_cache.country = country
        write_file(DATA_BASE .. "/location.json", '{"country":"' .. country .. '"}')
    end
end

-- ============ CACHE ============
local function read_cache(key)
    local content = read_file(DATA_BASE .. "/cache_" .. key .. ".txt")
    if not content then return nil end
    local ok, data = pcall(load("return " .. content))
    if ok and type(data) == "table" then return data end
    return nil
end

local function write_cache(key, data)
    local parts = {}
    for k, v in pairs(data) do
        if type(v) == "table" then
            local arr = {}
            for _, val in ipairs(v) do
                arr[#arr + 1] = tostring(val)
            end
            parts[#parts + 1] = k .. "={" .. table.concat(arr, ",") .. "}"
        else
            parts[#parts + 1] = k .. "=" .. tostring(v)
        end
    end
    write_file(DATA_BASE .. "/cache_" .. key .. ".txt", "{" .. table.concat(parts, ",") .. "}")
end

-- ============ FETCH MARKETS (all 12 coins, single API call) ============
local function fetch_markets()
    local ids = {}
    for _, a in ipairs(assets) do
        ids[#ids + 1] = a.cg_id
    end
    local url = "https://api.coingecko.com/api/v3/coins/markets?vs_currency=usd&ids="
        .. table.concat(ids, ",") .. "&price_change_percentage=1h,7d,30d,1y&order=market_cap_desc"

    local resp = run(CURL .. ' -s -S --connect-timeout 5 --max-time 15 "' .. url .. '" 2>/dev/null')
    if not resp or resp == "" then return false end

    local json_file = DATA_BASE .. "/_data.json"
    local py_script = DATA_BASE .. "/_parse.py"
    write_file(json_file, resp)
    write_file(py_script, [[
import sys, json
with open(sys.argv[1]) as f:
    data = json.load(f)
for d in data:
    print(d["id"], d.get("current_price", ""),
          d.get("price_change_percentage_1h_in_currency", ""),
          d.get("price_change_percentage_24h", ""),
          d.get("price_change_percentage_7d_in_currency", ""),
          d.get("price_change_percentage_30d_in_currency", ""),
          d.get("price_change_percentage_1y_in_currency", ""))
]])
    local output = run('python3 "' .. py_script .. '" "' .. json_file .. '" 2>/dev/null')
    os.remove(py_script)
    os.remove(json_file)

    if not output or output == "" then return false end

    local got_any = false
    for line in output:gmatch("[^\n]+") do
        local cg_id, price, pct_1h, pct_24h, pct_7d, pct_30d, pct_1y =
            line:match("^(%S+)%s+(%S*)%s+(%S*)%s+(%S*)%s+(%S*)%s+(%S*)%s+(%S*)%s*$")
        if cg_id and price ~= "" then
            local asset = nil
            for _, a in ipairs(assets) do
                if a.cg_id == cg_id then asset = a; break end
            end
            if asset then
                local data = { cur = tonumber(price) }
                if pct_1h ~= "" then data.pct_1h = tonumber(pct_1h) end
                if pct_24h ~= "" then data.pct_1d = tonumber(pct_24h) end
                if pct_7d ~= "" then data.pct_1w = tonumber(pct_7d) end
                if pct_30d ~= "" then data.pct_1m = tonumber(pct_30d) end
                if pct_1y ~= "" then data.pct_1y = tonumber(pct_1y) end
                write_cache(asset.name, data)
                got_any = true
            end
        end
    end

    return got_any
end

-- ============ FETCH FOREX ============
local function fetch_forex()
    local resp = run(CURL .. ' -s -S --connect-timeout 5 --max-time 10 "https://open.er-api.com/v6/latest/USD" 2>/dev/null')
    if not resp or resp == "" then return false end

    local rates = {}
    for code, val in resp:gmatch('"(%w+)"%s*:%s*([%d%.]+)') do
        rates[code] = tonumber(val)
    end

    if next(rates) == nil then return false end
    write_cache("forex", rates)
    return true
end

-- ============ MAIN UPDATE ============
function conky_update_finnhub()
    fetch_location()

    local now = os.time()
    local got_data = false

    -- Markets (all 12 coins, every 240s)
    if now - last_markets_fetch >= MARKETS_TTL then
        if fetch_markets() then
            last_markets_fetch = now
            got_data = true
        end
    end

    -- Forex (every 240s)
    if now - last_forex_fetch >= FOREX_TTL then
        if fetch_forex() then
            last_forex_fetch = now
        end
    end

    return ""
end

-- ============ GETTER HELPERS ============
local function get_pct(asset_idx, field)
    local asset = assets[asset_idx]
    if not asset then return nil end
    local data = read_cache(asset.name)
    if not data then return nil end
    return data[field]
end

-- ============ FOREX ============
local function get_forex_rate(code)
    local rates = read_cache("forex")
    if not rates then return nil end
    return rates[code]
end

function conky_fn_forex_row()
    fetch_location()
    local country = location_cache.country

    local parts = {}
    local local_code = country_currency[country]
    if local_code and local_code ~= "USD" then
        local rate = get_forex_rate(local_code)
        local sym = currency_symbols[local_code] or local_code
        if rate then
            parts[#parts + 1] = "${color1}1 USD = " .. string.format("%.2f", rate) .. " " .. sym .. "${color}"
        end
    end

    local eur_rate = get_forex_rate("EUR")
    if eur_rate then
        if #parts > 0 then parts[#parts + 1] = "  ${color2}|${color}  " end
        local sym = currency_symbols["EUR"] or "€"
        parts[#parts + 1] = "${color1}1 USD = " .. string.format("%.2f", eur_rate) .. " " .. sym .. "${color}"
    end

    local jpy_rate = get_forex_rate("JPY")
    if jpy_rate then
        if #parts > 0 then parts[#parts + 1] = "  ${color2}|${color}  " end
        local sym = currency_symbols["JPY"] or "¥"
        parts[#parts + 1] = "${color1}1 USD = " .. string.format("%.2f", jpy_rate) .. " " .. sym .. "${color}"
    end

    if #parts == 0 then return "..." end
    return table.concat(parts)
end

-- ============ DYNAMIC GETTERS ============
local function format_cell(field, idx)
    local val = get_pct(idx, field)
    if val == nil then return " --" end
    local fmt = string.format("%+.1f", val)
    if val > 0 then
        return "${color4}▲${color}" .. fmt:sub(2) .. "%"
    elseif val < 0 then
        return "${color5}▼${color}" .. fmt:sub(2) .. "%"
    else
        return "${color1}─${color}0.0%"
    end
end

for i = 1, 12 do
    local idx = i
    _G["conky_fn_name_" .. idx] = function() return assets[idx].name end
    _G["conky_fn_cell_1h_" .. idx] = function() return format_cell("pct_1h", idx) end
    _G["conky_fn_cell_1d_" .. idx] = function() return format_cell("pct_1d", idx) end
    _G["conky_fn_cell_1w_" .. idx] = function() return format_cell("pct_1w", idx) end
    _G["conky_fn_cell_1m_" .. idx] = function() return format_cell("pct_1m", idx) end
    _G["conky_fn_cell_1y_" .. idx] = function() return format_cell("pct_1y", idx) end
end

