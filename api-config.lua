-- api-config.env - Unified API Configuration Module
-- Merges env.lua, lastfm/config.lua, and overload/weather_config.lua
-- Parses .env file and provides both Last.fm and OpenWeatherMap API configurations
-- Usage: local config = require("api-config")
--        config.lastfm for Last.fm API config
--        config.weather for Weather API config
--        config.get("KEY") for environment variables

local api_config = {}
local env_config = {}
local env_loaded = false

-- Helper function to trim whitespace
local function trim(s)
    return s:match("^%s*(.-)%s*$")
end

-- Load and parse .env file
local function load_env()
    if env_loaded then return end
    
    local home = os.getenv("HOME")
    local env_file = home .. "/.conky/conky-themes-repo/.env"
    
    local f = io.open(env_file, "r")
    if not f then
        -- Try relative path from script location
        local script_dir = debug.getinfo(1, "S").source:match("^@(.*/)")
        env_file = script_dir and script_dir .. ".env" or ".env"
        f = io.open(env_file, "r")
        if not f then
            return false
        end
    end
    
    for line in f:lines() do
        -- Skip empty lines and comments
        if line:match("^%s*[^#]") and line:match("=") then
            local key, value = line:match("^%s*([^=]+)%s*=%s*(.*)%s*$")
            if key and value then
                key = trim(key)
                value = trim(value)
                -- Remove quotes if present
                if value:match('^".*"$') or value:match("^'.*'$") then
                    value = value:sub(2, -2)
                end
                env_config[key] = value
            end
        end
    end
    f:close()
    env_loaded = true
    return true
end

-- Get a value from .env by key
function api_config.get(key, default)
    if not env_loaded then load_env() end
    return env_config[key] or default or nil
end

-- Get all config as table
function api_config.get_all()
    if not env_loaded then load_env() end
    return env_config
end

-- Reload .env file (in case it changed)
function api_config.reload()
    env_config = {}
    env_loaded = false
    load_env()
    init_lastfm()
    init_weather()
end

-- ============================================
-- Last.fm API Configuration (from config.lua)
-- ============================================
function init_lastfm()
    api_config.lastfm = {}
    
    -- Last.fm API credentials
    -- Get your API key from: https://www.last.fm/api/account/create
    api_config.lastfm.API_KEY = api_config.get("LASTFM_API_KEY") or "YOUR_API_KEY_HERE"
    api_config.lastfm.USERNAME = api_config.get("LASTFM_USERNAME") or "YOUR_LASTFM_USERNAME_HERE"
    
    -- API endpoints
    api_config.lastfm.BASE_URL = "https://ws.audioscrobbler.com/2.0/"
    
    -- API methods
    api_config.lastfm.METHODS = {
        RECENT_TRACKS = "user.getrecenttracks",
        TRACK_INFO = "track.getInfo",
        USER_TRACK_SCROBBLES = "user.getTrackScrobbles"
    }
    
    -- Helper function to build API URLs
    function api_config.lastfm.build_url(method, params)
        local url = api_config.lastfm.BASE_URL .. "?method=" .. method .. "&api_key=" .. api_config.lastfm.API_KEY .. "&format=json"
        
        if params then
            for key, value in pairs(params) do
                local encoded_value = tostring(value):gsub(" ", "%%20"):gsub("&", "%%26")
                url = url .. "&" .. key .. "=" .. encoded_value
            end
        end
        
        return url
    end
end

-- ============================================
-- OpenWeatherMap API Configuration (from weather_config.lua)
-- ============================================
function init_weather()
    api_config.weather = {}
    
    -- OpenWeatherMap API credentials
    -- Get your free API key at: https://openweathermap.org/api
    api_config.weather.API_KEY = api_config.get("WEATHER_API_KEY") or "YOUR_API_KEY_HERE"
    api_config.weather.NAME = api_config.get("WEATHER_NAME") or "Default"
    
    -- API endpoints
    api_config.weather.BASE_URL = "https://api.openweathermap.org/data/2.5/"
    api_config.weather.ONECALL_URL = "https://api.openweathermap.org/data/3.0/onecall"
    api_config.weather.GEO_URL = "http://ip-api.com/json/?fields=lat,lon,city,country"
    
    -- Units (metric = Celsius, imperial = Fahrenheit)
    api_config.weather.UNITS = api_config.get("WEATHER_UNITS") or "metric"
    
    -- Cache settings
    api_config.weather.CACHE_DIR = os.getenv("HOME") .. "/.cache"
    api_config.weather.CACHE_FILE = api_config.weather.CACHE_DIR .. "/weather2.txt"
    api_config.weather.FORECAST_CACHE = api_config.weather.CACHE_DIR .. "/weather_forecast.txt"
    
    -- Update interval in seconds (10 minutes)
    api_config.weather.UPDATE_INTERVAL = 600
    
    -- Helper function to build API URLs
    function api_config.weather.build_current_url(lat, lon)
        return api_config.weather.BASE_URL .. "weather?lat=" .. lat .. "&lon=" .. lon .. 
               "&appid=" .. api_config.weather.API_KEY .. "&units=" .. api_config.weather.UNITS
    end
    
    function api_config.weather.build_forecast_url(lat, lon)
        return api_config.weather.BASE_URL .. "forecast?lat=" .. lat .. "&lon=" .. lon .. 
               "&appid=" .. api_config.weather.API_KEY .. "&units=" .. api_config.weather.UNITS
    end
    
    -- OneCall API for comprehensive data (current, forecast, moon phases)
    function api_config.weather.build_onecall_url(lat, lon)
        return "https://api.openweathermap.org/data/2.5/onecall?lat=" .. lat .. "&lon=" .. lon .. 
               "&exclude=minutely,alerts&appid=" .. api_config.weather.API_KEY .. "&units=" .. api_config.weather.UNITS
    end
end

-- Initialize on require
load_env()
init_lastfm()
init_weather()

return api_config
