-- Weather Lua Script for Conky
-- Uses OpenWeatherMap API with automatic location detection
-- Uses lua_draw_hook for image rendering with Cairo
-- Icons stored locally in assets/icons/

-- Cairo is loaded by conky automatically when lua_draw_hook is used

-- Load the API configuration
local script_dir = debug.getinfo(1, "S").source:match("^@(.*/)")
if not script_dir then script_dir = "/home/digerati/.conky/conky-themes-repo/overload/" end
package.path = package.path .. ";" .. script_dir .. "?.lua"

local config = require("weather_api_config")

-- Icons directory - absolute path
local icons_dir = script_dir .. "assets/icons/"

-- Weather description to MET Norway icon name mapping
local icon_mapping = {
    -- Clear conditions
    ["clear sky"] = { day = "clearsky_day", night = "clearsky_night" },
    ["sunny"] = { day = "clearsky_day", night = "clearsky_night" },
    
    -- Few/scattered clouds
    ["few clouds"] = { day = "fair_day", night = "fair_night" },
    ["scattered clouds"] = { day = "partlycloudy_day", night = "partlycloudy_night" },
    
    -- Cloudy
    ["broken clouds"] = { day = "cloudy", night = "cloudy" },
    ["overcast clouds"] = { day = "cloudy", night = "cloudy" },
    
    -- Rain
    ["light rain"] = { day = "lightrain", night = "lightrain" },
    ["moderate rain"] = { day = "rain", night = "rain" },
    ["heavy intensity rain"] = { day = "heavyrain", night = "heavyrain" },
    ["very heavy rain"] = { day = "heavyrain", night = "heavyrain" },
    ["extreme rain"] = { day = "heavyrain", night = "heavyrain" },
    ["freezing rain"] = { day = "sleet", night = "sleet" },
    ["rain"] = { day = "rain", night = "rain" },
    
    -- Drizzle
    ["light intensity drizzle"] = { day = "lightrain", night = "lightrain" },
    ["drizzle"] = { day = "lightrain", night = "lightrain" },
    ["heavy intensity drizzle"] = { day = "rain", night = "rain" },
    ["light intensity drizzle rain"] = { day = "lightrain", night = "lightrain" },
    ["drizzle rain"] = { day = "lightrain", night = "lightrain" },
    ["heavy intensity drizzle rain"] = { day = "rain", night = "rain" },
    ["shower rain and drizzle"] = { day = "rainshowers_day", night = "rainshowers_night" },
    ["heavy shower rain and drizzle"] = { day = "heavyrainshowers_day", night = "heavyrainshowers_night" },
    ["shower drizzle"] = { day = "lightrainshowers_day", night = "lightrainshowers_night" },
    
    -- Showers
    ["light intensity shower rain"] = { day = "lightrainshowers_day", night = "lightrainshowers_night" },
    ["shower rain"] = { day = "rainshowers_day", night = "rainshowers_night" },
    ["heavy intensity shower rain"] = { day = "heavyrainshowers_day", night = "heavyrainshowers_night" },
    ["ragged shower rain"] = { day = "rainshowers_day", night = "rainshowers_night" },
    
    -- Thunderstorm
    ["thunderstorm with light rain"] = { day = "lightrainandthunder", night = "lightrainandthunder" },
    ["thunderstorm with rain"] = { day = "rainandthunder", night = "rainandthunder" },
    ["thunderstorm with heavy rain"] = { day = "heavyrainandthunder", night = "heavyrainandthunder" },
    ["light thunderstorm"] = { day = "rainandthunder", night = "rainandthunder" },
    ["thunderstorm"] = { day = "rainandthunder", night = "rainandthunder" },
    ["heavy thunderstorm"] = { day = "heavyrainandthunder", night = "heavyrainandthunder" },
    ["ragged thunderstorm"] = { day = "rainandthunder", night = "rainandthunder" },
    ["thunderstorm with light drizzle"] = { day = "lightrainandthunder", night = "lightrainandthunder" },
    ["thunderstorm with drizzle"] = { day = "rainandthunder", night = "rainandthunder" },
    ["thunderstorm with heavy drizzle"] = { day = "heavyrainandthunder", night = "heavyrainandthunder" },
    
    -- Snow
    ["light snow"] = { day = "lightsnow", night = "lightsnow" },
    ["snow"] = { day = "snow", night = "snow" },
    ["heavy snow"] = { day = "heavysnow", night = "heavysnow" },
    ["sleet"] = { day = "sleet", night = "sleet" },
    ["light shower sleet"] = { day = "lightsleetshowers_day", night = "lightsleetshowers_night" },
    ["shower sleet"] = { day = "sleetshowers_day", night = "sleetshowers_night" },
    ["light rain and snow"] = { day = "lightsleet", night = "lightsleet" },
    ["rain and snow"] = { day = "sleet", night = "sleet" },
    ["light shower snow"] = { day = "lightsnowshowers_day", night = "lightsnowshowers_night" },
    ["shower snow"] = { day = "snowshowers_day", night = "snowshowers_night" },
    ["heavy shower snow"] = { day = "heavysnowshowers_day", night = "heavysnowshowers_night" },
    
    -- Atmosphere
    ["mist"] = { day = "fog", night = "fog" },
    ["smoke"] = { day = "fog", night = "fog" },
    ["haze"] = { day = "fog", night = "fog" },
    ["sand/dust whirls"] = { day = "fog", night = "fog" },
    ["fog"] = { day = "fog", night = "fog" },
    ["sand"] = { day = "fog", night = "fog" },
    ["dust"] = { day = "fog", night = "fog" },
    ["volcanic ash"] = { day = "fog", night = "fog" },
    ["squalls"] = { day = "fog", night = "fog" },
    ["tornado"] = { day = "fog", night = "fog" }
}

-- Runtime storage (all data stored here)
local weather_data = {
    last_update = 0,
    lat = nil,
    lon = nil,
    city = nil,
    country = nil,
    current = {
        temp = "N/A",
        temp_min = "N/A",
        temp_max = "N/A",
        humidity = "N/A",
        pressure = "N/A",
        precipitation = "0",
        wind_speed = "0",
        wind_deg = 0,
        wind_dir = "N/A",
        visibility_km = "10.0",
        description = "Unknown",
        icon = "01d",
        icon_path = nil
    },
    hourly_forecast = {},
    daily_forecast = {},
    forecast = {},
    moon = { name = "Unknown", icon = "🌑" },
    update_time = "N/A",
    current_date = "N/A"
}

-- Image positions for draw hook (x, y, size)
local image_positions = {
    current = { x = 10, y = 45, size = 100 },
    -- Forecast icons can be added here if needed
}

-- Moon phases
local moon_phases = {
    [0] = { name = "New Moon", icon = "🌑" },
    [1] = { name = "Waxing Crescent", icon = "🌒" },
    [2] = { name = "First Quarter", icon = "🌓" },
    [3] = { name = "Waxing Gibbous", icon = "🌔" },
    [4] = { name = "Full Moon", icon = "🌕" },
    [5] = { name = "Waning Gibbous", icon = "🌖" },
    [6] = { name = "Last Quarter", icon = "🌗" },
    [7] = { name = "Waning Crescent", icon = "🌘" }
}

-- Wind direction arrows
local wind_arrows = {
    ["N"] = "↑", ["NNE"] = "↗", ["NE"] = "↗", ["ENE"] = "↗",
    ["E"] = "→", ["ESE"] = "↘", ["SE"] = "↘", ["SSE"] = "↘",
    ["S"] = "↓", ["SSW"] = "↙", ["SW"] = "↙", ["WSW"] = "↙",
    ["W"] = "←", ["WNW"] = "↖", ["NW"] = "↖", ["NNW"] = "↖"
}

-- Helper: execute shell command
local function exec_command(cmd)
    local handle = io.popen(cmd)
    if not handle then return nil end
    local result = handle:read("*a")
    handle:close()
    return result
end

-- Determine if it's day or night based on icon code suffix or time
local function is_daytime(icon_code)
    if icon_code and icon_code:sub(-1) == "n" then
        return false
    elseif icon_code and icon_code:sub(-1) == "d" then
        return true
    end
    -- Fallback: check current hour (6am-6pm is day)
    local hour = tonumber(os.date("%H"))
    return hour >= 6 and hour < 18
end

-- Get icon path from weather description
local function get_icon_path(description, icon_code)
    description = description and description:lower() or "clear sky"
    local mapping = icon_mapping[description]
    
    if mapping then
        local time_of_day = is_daytime(icon_code) and "day" or "night"
        return icons_dir .. mapping[time_of_day] .. ".png"
    end
    
    -- Fallback to clearsky if no mapping found
    local time_of_day = is_daytime(icon_code) and "day" or "night"
    return icons_dir .. "clearsky_" .. time_of_day .. ".png"
end

-- Wind direction conversion
local function deg_to_direction(deg)
    deg = tonumber(deg) or 0
    local directions = {"N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"}
    local index = math.floor((deg + 11.25) / 22.5) % 16 + 1
    return directions[index]
end

-- JSON parsing helpers
local function parse_json_value(json, key)
    local pattern = '"' .. key .. '"%s*:%s*([^,}%]]+)'
    local match = json:match(pattern)
    if match then
        -- Wrap in parentheses to discard second return value from gsub
        return (match:gsub('^"', ''):gsub('"$', ''):gsub('%s+$', ''))
    end
    return nil
end

local function parse_nested_json(json, parent_key, child_key)
    local parent_pattern = '"' .. parent_key .. '"%s*:%s*%{([^}]+)%}'
    local parent_match = json:match(parent_pattern)
    if parent_match then
        return parse_json_value("{" .. parent_match .. "}", child_key)
    end
    return nil
end

local function parse_array_item(json, array_key, index)
    local pattern = '"' .. array_key .. '"%s*:%s*%[(.-)%]'
    local array_match = json:match(pattern)
    if array_match then
        local count = 0
        for item in array_match:gmatch('%{([^}]+)%}') do
            count = count + 1
            if count == index then
                return "{" .. item .. "}"
            end
        end
    end
    return nil
end

-- Get location from IP
local function get_location()
    if weather_data.lat and weather_data.lon then
        return weather_data.lat, weather_data.lon
    end
    local geo_data = exec_command('curl -s "' .. config.GEO_URL .. '"')
    if geo_data then
        weather_data.lat = parse_json_value(geo_data, "lat")
        weather_data.lon = parse_json_value(geo_data, "lon")
        weather_data.city = parse_json_value(geo_data, "city")
        weather_data.country = parse_json_value(geo_data, "country")
        return weather_data.lat, weather_data.lon
    end
    return nil, nil
end

-- Calculate moon phase
local function get_moon_phase(timestamp)
    local known_new_moon = 947182440
    local lunar_cycle = 29.53058867 * 24 * 60 * 60
    local ts = tonumber(timestamp) or os.time()
    local days_since = (ts - known_new_moon) / lunar_cycle
    local phase = days_since - math.floor(days_since)
    local phase_index = math.floor(phase * 8 + 0.5) % 8
    return moon_phases[phase_index]
end

-- Fetch current weather
local function fetch_current_weather(lat, lon)
    local url = config.build_current_url(lat, lon)
    local data = exec_command('curl -s "' .. url .. '"')
    if not data or data == "" then return false end
    
    weather_data.current.temp = parse_nested_json(data, "main", "temp") or "N/A"
    weather_data.current.temp_min = parse_nested_json(data, "main", "temp_min") or "N/A"
    weather_data.current.temp_max = parse_nested_json(data, "main", "temp_max") or "N/A"
    weather_data.current.humidity = parse_nested_json(data, "main", "humidity") or "N/A"
    weather_data.current.pressure = parse_nested_json(data, "main", "pressure") or "N/A"
    
    local visibility = parse_json_value(data, "visibility") or "10000"
    weather_data.current.visibility_km = string.format("%.1f", (tonumber(visibility) or 10000) / 1000)
    
    weather_data.current.wind_speed = parse_nested_json(data, "wind", "speed") or "0"
    weather_data.current.wind_deg = tonumber(parse_nested_json(data, "wind", "deg")) or 0
    weather_data.current.wind_dir = deg_to_direction(weather_data.current.wind_deg)
    
    local weather_array = parse_array_item(data, "weather", 1)
    if weather_array then
        weather_data.current.description = parse_json_value(weather_array, "description") or "Unknown"
        weather_data.current.icon = parse_json_value(weather_array, "icon") or "01d"
    end
    
    weather_data.current.icon_path = get_icon_path(weather_data.current.description, weather_data.current.icon)
    
    -- Update symlink for conky ${image} to use
    os.execute('ln -sf "' .. weather_data.current.icon_path .. '" /tmp/conky_weather_icon.png')
    
    local rain = data:match('"rain"%s*:%s*%{[^}]*"1h"%s*:%s*([%d%.]+)')
    weather_data.current.precipitation = rain or "0"
    
    weather_data.moon = get_moon_phase(os.time())
    weather_data.update_time = os.date("%Y-%m-%d %H:%M")
    weather_data.current_date = os.date("%A, %B %d, %Y")
    
    return true
end

-- Fetch forecast
local function fetch_forecast(lat, lon)
    local url = config.build_forecast_url(lat, lon)
    local data = exec_command('curl -s "' .. url .. '"')
    if not data or data == "" then return false end
    
    weather_data.forecast = {}
    weather_data.hourly_forecast = {}
    weather_data.daily_forecast = {}
    
    local daily_data = {}
    local list_pattern = '"list"%s*:%s*%[(.+)%]'
    local list_match = data:match(list_pattern)
    
    if list_match then
        local pos = 1
        local index = 0
        
        while true do
            local dt_start, dt_end, dt = list_match:find('"dt":(%d+)', pos)
            if not dt_start then break end
            
            index = index + 1
            local forecast = { dt = dt }
            
            local next_dt = list_match:find('"dt":', dt_end + 1)
            local chunk_end = next_dt and (next_dt - 1) or #list_match
            local chunk = list_match:sub(dt_start, chunk_end)
            
            forecast.temp = tonumber(chunk:match('"temp":([%d%.%-]+)')) or 0
            forecast.temp_min = tonumber(chunk:match('"temp_min":([%d%.%-]+)')) or forecast.temp
            forecast.temp_max = tonumber(chunk:match('"temp_max":([%d%.%-]+)')) or forecast.temp
            forecast.humidity = tonumber(chunk:match('"humidity":(%d+)')) or 0
            forecast.description = chunk:match('"description":"([^"]+)"') or "Unknown"
            forecast.icon = chunk:match('"icon":"([^"]+)"') or "01d"
            
            local vis = chunk:match('"visibility":(%d+)')
            forecast.visibility_km = vis and string.format("%.1f", tonumber(vis) / 1000) or "10.0"
            
            local rain_3h = chunk:match('"3h":([%d%.]+)')
            forecast.precipitation = tonumber(rain_3h) or 0
            
            -- Probability of precipitation (0-1 from API, convert to %)
            local pop = chunk:match('"pop":([%d%.]+)')
            forecast.pop = tonumber(pop) or 0
            
            local day_key = os.date("%Y-%m-%d", tonumber(forecast.dt))
            forecast.date = os.date("%a %d", tonumber(forecast.dt))
            forecast.day_name = os.date("%A", tonumber(forecast.dt))
            forecast.time = os.date("%H:%M", tonumber(forecast.dt))
            forecast.icon_path = get_icon_path(forecast.description, forecast.icon)
            
            -- Store hourly (first 8 = 24h of 3-hour intervals)
            if index <= 8 then
                table.insert(weather_data.hourly_forecast, {
                    time = forecast.time,
                    date = forecast.date,
                    temp = string.format("%.0f", forecast.temp),
                    humidity = string.format("%.0f", forecast.humidity),
                    visibility_km = forecast.visibility_km,
                    precipitation = string.format("%.1f", forecast.precipitation),
                    pop = string.format("%.2f", forecast.pop),
                    description = forecast.description,
                    icon = forecast.icon,
                    icon_path = forecast.icon_path
                })
            end
            
            -- Aggregate daily
            if not daily_data[day_key] then
                daily_data[day_key] = {
                    date = forecast.date,
                    day_name = forecast.day_name,
                    dt = tonumber(forecast.dt),
                    temp_min = forecast.temp_min,
                    temp_max = forecast.temp_max,
                    humidity_sum = forecast.humidity,
                    humidity_count = 1,
                    visibility_sum = tonumber(forecast.visibility_km) or 10,
                    visibility_count = 1,
                    precipitation = forecast.precipitation,
                    pop_max = forecast.pop,
                    description = forecast.description,
                    icon = forecast.icon
                }
            else
                local d = daily_data[day_key]
                d.temp_min = math.min(d.temp_min, forecast.temp_min)
                d.temp_max = math.max(d.temp_max, forecast.temp_max)
                d.humidity_sum = d.humidity_sum + forecast.humidity
                d.humidity_count = d.humidity_count + 1
                d.visibility_sum = d.visibility_sum + (tonumber(forecast.visibility_km) or 10)
                d.visibility_count = d.visibility_count + 1
                d.precipitation = d.precipitation + forecast.precipitation
                d.pop_max = math.max(d.pop_max or 0, forecast.pop)
                local hour = tonumber(os.date("%H", tonumber(forecast.dt)))
                if hour >= 11 and hour <= 14 then
                    d.description = forecast.description
                    d.icon = forecast.icon
                end
            end
            
            table.insert(weather_data.forecast, forecast)
            pos = dt_end + 1
            if index >= 40 then break end
        end
    end
    
    -- Sort and store daily forecast
    local sorted_days = {}
    for day_key, _ in pairs(daily_data) do
        table.insert(sorted_days, day_key)
    end
    table.sort(sorted_days)
    
    local day_count = 0
    for _, day_key in ipairs(sorted_days) do
        local d = daily_data[day_key]
        table.insert(weather_data.daily_forecast, {
            date = d.date,
            day_name = d.day_name,
            temp_min = string.format("%.0f", d.temp_min),
            temp_max = string.format("%.0f", d.temp_max),
            temp = string.format("%.0f", (d.temp_min + d.temp_max) / 2),
            humidity = string.format("%.0f", d.humidity_sum / d.humidity_count),
            visibility_km = string.format("%.1f", d.visibility_sum / d.visibility_count),
            precipitation = string.format("%.1f", d.precipitation),
            pop = string.format("%.2f", d.pop_max or 0),
            description = d.description,
            icon = d.icon,
            icon_path = get_icon_path(d.description, d.icon),
            moon = get_moon_phase(d.dt)
        })
        day_count = day_count + 1
        if day_count >= 8 then break end
    end
    
    return true
end

-- ============ MAIN UPDATE FUNCTION ============
function conky_update_weather()
    local current_time = os.time()
    if current_time - weather_data.last_update < config.UPDATE_INTERVAL then
        return ""
    end
    
    local lat, lon = get_location()
    if not lat or not lon then return "" end
    
    fetch_current_weather(lat, lon)
    fetch_forecast(lat, lon)
    
    weather_data.last_update = current_time
    return ""
end

-- ============ CAIRO DRAW HOOK ============
-- This function is called by conky's lua_draw_hook_post
function conky_main()
    if conky_window == nil then return end
    
    -- Check if we can use Cairo (need X11, won't work on pure Wayland)
    if not cairo_xlib_surface_create then
        -- Cairo X11 not available, skip drawing
        return
    end
    
    local cs = cairo_xlib_surface_create(
        conky_window.display,
        conky_window.drawable,
        conky_window.visual,
        conky_window.width,
        conky_window.height
    )
    local cr = cairo_create(cs)
    
    -- Draw current weather icon
    local icon_path = weather_data.current.icon_path
    if icon_path then
        local pos = image_positions.current
        local file = io.open(icon_path, "r")
        if file then
            file:close()
            local image = cairo_image_surface_create_from_png(icon_path)
            local status = cairo_surface_status(image)
            if status == CAIRO_STATUS_SUCCESS then
                local img_w = cairo_image_surface_get_width(image)
                local img_h = cairo_image_surface_get_height(image)
                local scale = pos.size / math.max(img_w, img_h)
                
                cairo_save(cr)
                cairo_translate(cr, pos.x, pos.y)
                cairo_scale(cr, scale, scale)
                cairo_set_source_surface(cr, image, 0, 0)
                cairo_paint(cr)
                cairo_restore(cr)
            end
            cairo_surface_destroy(image)
        end
    end
    
    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end

-- ============ GETTER FUNCTIONS ============
function conky_moon_phase() return weather_data.moon.icon .. " " .. weather_data.moon.name end
function conky_moon_icon() return weather_data.moon.icon end
function conky_moon_name() return weather_data.moon.name end
function conky_get_temp() return math.floor(weather_data.current.temp + 0.5) end
function conky_get_mintemp() return weather_data.current.temp_min end
function conky_get_maxtemp() return weather_data.current.temp_max end
function conky_get_humidity() return weather_data.current.humidity end
function conky_get_pressure() return weather_data.current.pressure end
function conky_get_precipitation() return weather_data.current.precipitation end
function conky_get_wind() return weather_data.current.wind_speed end
function conky_get_wind_dir() return weather_data.current.wind_dir end
function conky_get_wind_dir_icon() return " " .. (wind_arrows[weather_data.current.wind_dir] or "") end
function conky_get_visibility() return weather_data.current.visibility_km end
function conky_get_description()
    local desc = weather_data.current.description or ""
    return (desc:gsub("(%a)([%w_']*)", function(first, rest) return first:upper() .. rest:lower() end))
end
function conky_get_city() return weather_data.city or "Unknown" end
function conky_get_country() return weather_data.country and (", " .. weather_data.country) or "" end
function conky_get_date() return weather_data.current_date end
function conky_get_update_time() return weather_data.update_time end

function conky_get_forecast_mintemp()
    return weather_data.daily_forecast[1] and weather_data.daily_forecast[1].temp_min or weather_data.current.temp_min
end
function conky_get_forecast_maxtemp()
    return weather_data.daily_forecast[1] and weather_data.daily_forecast[1].temp_max or weather_data.current.temp_max
end

-- ============ HOURLY FORECAST (Slot 1 = next 3 hours) ============
local function get_hourly_field(index, field)
    local f = weather_data.hourly_forecast[index]
    return f and f[field] or "N/A"
end

function conky_forecast_day_1() return get_hourly_field(1, "time") end
function conky_forecast_weather_1() return get_hourly_field(1, "description") end
function conky_forecast_temp_1() return get_hourly_field(1, "temp") end
function conky_forecast_humidity_1() return get_hourly_field(1, "humidity") end
function conky_forecast_visibility_1() return get_hourly_field(1, "visibility_km") end
function conky_forecast_precipitation_1() return get_hourly_field(1, "precipitation") end
function conky_forecast_pop_1() return get_hourly_field(1, "pop") end
function conky_forecast_icon_1() return get_hourly_field(1, "icon_path") end

-- ============ DAILY FORECAST (Slots 2-7) ============
local function get_daily_field(day, field)
    local f = weather_data.daily_forecast[day]
    return f and f[field] or "N/A"
end

function conky_forecast_day_2() return get_daily_field(1, "date") end
function conky_forecast_weather_2() return get_daily_field(1, "description") end
function conky_forecast_temp_2() return get_daily_field(1, "temp") end
function conky_forecast_humidity_2() return get_daily_field(1, "humidity") end
function conky_forecast_visibility_2() return get_daily_field(1, "visibility_km") end
function conky_forecast_precipitation_2() return get_daily_field(1, "precipitation") end
function conky_forecast_pop_2() return get_daily_field(1, "pop") end
function conky_forecast_icon_2() return get_daily_field(1, "icon_path") end

function conky_forecast_day_3() return get_daily_field(2, "date") end
function conky_forecast_weather_3() return get_daily_field(2, "description") end
function conky_forecast_temp_3() return get_daily_field(2, "temp") end
function conky_forecast_humidity_3() return get_daily_field(2, "humidity") end
function conky_forecast_visibility_3() return get_daily_field(2, "visibility_km") end
function conky_forecast_precipitation_3() return get_daily_field(2, "precipitation") end
function conky_forecast_pop_3() return get_daily_field(2, "pop") end
function conky_forecast_icon_3() return get_daily_field(2, "icon_path") end

function conky_forecast_day_4() return get_daily_field(3, "date") end
function conky_forecast_weather_4() return get_daily_field(3, "description") end
function conky_forecast_temp_4() return get_daily_field(3, "temp") end
function conky_forecast_humidity_4() return get_daily_field(3, "humidity") end
function conky_forecast_visibility_4() return get_daily_field(3, "visibility_km") end
function conky_forecast_precipitation_4() return get_daily_field(3, "precipitation") end
function conky_forecast_pop_4() return get_daily_field(3, "pop") end
function conky_forecast_icon_4() return get_daily_field(3, "icon_path") end

function conky_forecast_day_5() return get_daily_field(4, "date") end
function conky_forecast_weather_5() return get_daily_field(4, "description") end
function conky_forecast_temp_5() return get_daily_field(4, "temp") end
function conky_forecast_humidity_5() return get_daily_field(4, "humidity") end
function conky_forecast_visibility_5() return get_daily_field(4, "visibility_km") end
function conky_forecast_precipitation_5() return get_daily_field(4, "precipitation") end
function conky_forecast_pop_5() return get_daily_field(4, "pop") end
function conky_forecast_icon_5() return get_daily_field(4, "icon_path") end

function conky_forecast_day_6() return get_daily_field(5, "date") end
function conky_forecast_weather_6() return get_daily_field(5, "description") end
function conky_forecast_temp_6() return get_daily_field(5, "temp") end
function conky_forecast_humidity_6() return get_daily_field(5, "humidity") end
function conky_forecast_visibility_6() return get_daily_field(5, "visibility_km") end
function conky_forecast_precipitation_6() return get_daily_field(5, "precipitation") end
function conky_forecast_pop_6() return get_daily_field(5, "pop") end
function conky_forecast_icon_6() return get_daily_field(5, "icon_path") end

function conky_forecast_day_7() return get_daily_field(6, "date") end
function conky_forecast_weather_7() return get_daily_field(6, "description") end
function conky_forecast_temp_7() return get_daily_field(6, "temp") end
function conky_forecast_humidity_7() return get_daily_field(6, "humidity") end
function conky_forecast_visibility_7() return get_daily_field(6, "visibility_km") end
function conky_forecast_precipitation_7() return get_daily_field(6, "precipitation") end
function conky_forecast_pop_7() return get_daily_field(6, "pop") end
function conky_forecast_icon_7() return get_daily_field(6, "icon_path") end

function conky_forecast_day_8() return get_daily_field(7, "date") end
function conky_forecast_weather_8() return get_daily_field(7, "description") end
function conky_forecast_temp_8() return get_daily_field(7, "temp") end
function conky_forecast_humidity_8() return get_daily_field(7, "humidity") end
function conky_forecast_visibility_8() return get_daily_field(7, "visibility_km") end
function conky_forecast_precipitation_8() return get_daily_field(7, "precipitation") end
function conky_forecast_pop_8() return get_daily_field(7, "pop") end
function conky_forecast_icon_8() return get_daily_field(7, "icon_path") end

-- Initialize on load
conky_update_weather()
