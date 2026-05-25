-- Setup package paths early (before requiring JSON libs).
-- Conky's embedded Lua may not include Arch's default module dirs (e.g. /usr/share/lua/5.5).
local script_dir = debug.getinfo(1, "S").source:match("^@(.*/)")
if not script_dir then script_dir = "" end

local function add_package_path(p)
    if package and package.path and not package.path:find(p, 1, true) then
        package.path = package.path .. ";" .. p
    end
end

local function add_package_cpath(p)
    if package and package.cpath and not package.cpath:find(p, 1, true) then
        package.cpath = package.cpath .. ";" .. p
    end
end

-- Repo-local modules
add_package_path(script_dir .. "../?.lua")
add_package_path(script_dir .. "../config/?.lua")

-- System module dirs across common Lua versions (pure-Lua modules like dkjson are version-agnostic).
local versions = {"5.1", "5.2", "5.3", "5.4", "5.5"}
for _, v in ipairs(versions) do
    add_package_path("/usr/share/lua/" .. v .. "/?.lua")
    add_package_path("/usr/share/lua/" .. v .. "/?/init.lua")
    add_package_path("/usr/local/share/lua/" .. v .. "/?.lua")
    add_package_path("/usr/local/share/lua/" .. v .. "/?/init.lua")
    add_package_cpath("/usr/lib/lua/" .. v .. "/?.so")
    add_package_cpath("/usr/local/lib/lua/" .. v .. "/?.so")
end

-- Luajit module dirs (common if Conky is built against LuaJIT)
add_package_path("/usr/share/luajit-2.1/?.lua")
add_package_path("/usr/share/luajit-2.1/?/init.lua")

local json = nil
local json_backend = nil

do
    local ok, mod = pcall(require, "dkjson")
    if ok then
        json = mod
        json_backend = "dkjson"
    else
        ok, mod = pcall(require, "cjson.safe")
        if ok then
            json = mod
            json_backend = "cjson"
        else
            ok, mod = pcall(require, "cjson")
            if ok then
                json = mod
                json_backend = "cjson"
            end
        end
    end
end

local function json_decode(s)
    if not json then
        return nil, nil, "No JSON library found (install lua-dkjson or lua-cjson)"
    end

    if json_backend == "dkjson" then
        return json.decode(s)
    end

    local ok, res = pcall(json.decode, s)
    if ok then
        return res, nil, nil
    end
    return nil, nil, res
end

local function json_encode(t)
    if not json then
        return "{}"
    end

    if json_backend == "dkjson" then
        return json.encode(t, {indent = false})
    end

    local ok, res = pcall(json.encode, t)
    if ok then
        return res
    end
    return "{}"
end

-- Setup package path to find api-config.lua in parent/config directory
local api_config = require("api-config")
local api = api_config.lastfm

local function temp_base_dir()
    return os.getenv("TMPDIR") or os.getenv("XDG_RUNTIME_DIR") or "/tmp"
end

local function make_session_data_dir()
    math.randomseed(os.time())
    local uid = os.getenv("UID") or ""
    return temp_base_dir() .. "/conky-lastfm-" .. os.time() .. "-" .. math.random(100000, 999999) .. (uid ~= "" and ("-" .. uid) or "")
end

local function resolve_data_dir()
    if _G.CONKY_LASTFM_DATA_DIR and _G.CONKY_LASTFM_DATA_DIR ~= "" then
        return _G.CONKY_LASTFM_DATA_DIR
    end

    -- Prefer pulling the directory from the Conky config via template1
    if type(conky_parse) == "function" then
        local parsed = conky_parse("${template1}")
        if parsed and parsed ~= "" and parsed ~= "${template1}" then
            return parsed
        end
    end

    return make_session_data_dir()
end

-- CONFIG - Use per-launch temp directory
local DATA_DIR = resolve_data_dir()
_G.CONKY_LASTFM_DATA_DIR = DATA_DIR
local RAW_JSON = DATA_DIR .. "/raw.json"
local LOG_FILE = DATA_DIR .. "/debug.log"

local function find_curl()
    local handle = io.popen("command -v curl 2>/dev/null")
    if handle then
        local path = handle:read("*l")
        handle:close()
        if path and path ~= "" then
            return path
        end
    end

    -- Common fallbacks when PATH is minimal (common in Conky on some WMs).
    local f = io.open("/usr/bin/curl", "r")
    if f then
        f:close()
        return "/usr/bin/curl"
    end
    f = io.open("/bin/curl", "r")
    if f then
        f:close()
        return "/bin/curl"
    end
    return "curl"
end

local curl = find_curl()

-- Normalize os.execute() results across Lua versions.
-- Lua 5.1 may return a numeric exit code; Lua 5.2+ returns (ok, what, code).
local function exec_ok(cmd)
    local r1, _, r3 = os.execute(cmd)
    if type(r1) == "boolean" then
        return r1
    end
    if type(r1) == "number" then
        return r1 == 0
    end
    if type(r3) == "number" then
        return r3 == 0
    end
    return false
end

-- Logger function
local function log(message)
    local f = io.open(LOG_FILE, "a")
    if f then
        f:write(os.date("[%Y-%m-%d %H:%M:%S] ") .. tostring(message) .. "\n")
        f:close()
    end
end

-- Check for internet connectivity
local function check_internet()
    -- Probe Last.fm directly with short timeouts.
    -- More relevant than ip-api and avoids depending on `ping` being present/allowed.
    local probe_url = "https://ws.audioscrobbler.com/2.0/?format=json"
    local cmd = string.format('"%s" -s -S --connect-timeout 3 --max-time 5 -o /dev/null "%s" 2>/dev/null', curl, probe_url)
    return exec_ok(cmd)
end

-- Create assets dir
if not exec_ok("mkdir -p \"" .. DATA_DIR .. "\"") then
    -- If we can't create the requested directory, fall back to a new session dir.
    local fallback_dir = make_session_data_dir()
    if exec_ok("mkdir -p \"" .. fallback_dir .. "\"") then
        DATA_DIR = fallback_dir
        _G.CONKY_LASTFM_DATA_DIR = DATA_DIR
        RAW_JSON = DATA_DIR .. "/raw.json"
        LOG_FILE = DATA_DIR .. "/debug.log"
    end
end
log("Starting Last.fm script, caching to: " .. DATA_DIR)
log("Using api-config from: " .. tostring(api_config.env_path or "(unknown)"))
log("Last.fm USERNAME=" .. tostring(api.USERNAME) .. " API_KEY=" .. ((api.API_KEY and api.API_KEY ~= "" and api.API_KEY ~= "YOUR_API_KEY_HERE") and "present" or "missing"))
log("curl binary: " .. tostring(curl))
if json_backend then
    log("JSON backend: " .. tostring(json_backend))
else
    log("ERROR: No JSON library found (install lua-dkjson or lua-cjson)")
end

-- Initialize global variables
for i = 1, 3 do
    _G["artist"..i] = ""
    _G["track"..i] = ""
    _G["album"..i] = ""
    _G["duration"..i] = "-"
    _G["playcount"..i] = "-"
    _G["artistplays"..i] = "-"
end

-- Add global variable for now playing status
_G["nowplaying_status"] = "Not Playing"

-- Cache for API calls to avoid repeated requests
local cache = {}
local cache_timeout = 30 -- seconds

-- Cache for image URLs to avoid re-downloading the same image
-- Key: image_path, Value: {url = image_url, track_key = "artist|track"}
local image_url_cache = {}
local IMAGE_CACHE_FILE = DATA_DIR .. "/image_cache.json"

-- Load image cache from disk (persists across Conky restarts)
local function load_image_cache()
    local f = io.open(IMAGE_CACHE_FILE, "r")
    if f then
        local content = f:read("*a")
        f:close()
        local data = json_decode(content)
        if data then
            image_url_cache = data
            log("Loaded image cache from disk with " .. (function() local c=0; for _ in pairs(data) do c=c+1 end; return c end)() .. " entries")
        end
    end
end

-- Save image cache to disk
local function save_image_cache()
    local content = json_encode(image_url_cache)
    local f = io.open(IMAGE_CACHE_FILE, "w")
    if f then
        f:write(content)
        f:close()
    end
end

-- Load cache on script init
load_image_cache()

local function fetch_json()
    if not api or not api.USERNAME or api.USERNAME == "" or api.USERNAME == "YOUR_LASTFM_USERNAME_HERE" then
        log("Last.fm USERNAME is not configured (check api.env/.env loading)")
        return false
    end
    if not api.API_KEY or api.API_KEY == "" or api.API_KEY == "YOUR_API_KEY_HERE" then
        log("Last.fm API key is not configured (check api.env/.env loading)")
        return false
    end

    local url = api.build_url(api.METHODS.RECENT_TRACKS, {
        user = api.USERNAME,
        limit = 5
    })
    
    local temp_raw = RAW_JSON .. ".tmp"
    local cmd = string.format('"%s" -s -S --connect-timeout 5 --max-time 10 -o "%s" "%s" 2>/dev/null && mv "%s" "%s"', curl, temp_raw, url, temp_raw, RAW_JSON)
    if not exec_ok(cmd) then
        log("curl fetch failed (command exit != 0)")
        return false
    end

    local f = io.open(RAW_JSON, "r")
    if not f then
        log("raw.json missing after fetch")
        return false
    end

    local content = f:read("*a")
    f:close()
    if not content or content == "" then
        log("raw.json empty after fetch")
        return false
    end

    local data, _, err = json_decode(content)
    if not data then
        log("Failed to decode raw.json: " .. tostring(err))
        return false
    end

    if data.error or data.message then
        log("Last.fm API error " .. tostring(data.error) .. ": " .. tostring(data.message))
        return false
    end

    if not (data.recenttracks and data.recenttracks.track) then
        log("Last.fm response missing recenttracks.track")
        return false
    end

    return true
end

local function get_tracks()
    local f = io.open(RAW_JSON, "r")
    if not f then return {} end
    
    local content = f:read("*a")
    f:close()
    
    local data = json_decode(content)
    if not data or not data.recenttracks or not data.recenttracks.track then
        return {}
    end
    
    local tracks = data.recenttracks.track
    
    -- Handle single track as array
    if tracks.artist then 
        tracks = { tracks }
    end
    
    -- Filter out duplicate "now playing" tracks efficiently
    local filtered_tracks = {}
    local seen_tracks = {}
    
    for _, track in ipairs(tracks) do
        local artist = (track.artist and track.artist["#text"]) or "Unknown"
        local track_name = track.name or "Unknown"
        local track_key = artist .. "|" .. track_name
        local is_now_playing = track["@attr"] and track["@attr"]["nowplaying"] == "true"
        
        if not seen_tracks[track_key] then
            -- If this is "now playing", check if we have a scrobbled version
            if is_now_playing then
                local has_scrobbled = false
                for _, other in ipairs(tracks) do
                    local other_artist = (other.artist and other.artist["#text"]) or "Unknown"
                    local other_name = other.name or "Unknown"
                    local other_key = other_artist .. "|" .. other_name
                    local other_playing = other["@attr"] and other["@attr"]["nowplaying"] == "true"
                    
                    if track_key == other_key and not other_playing then
                        has_scrobbled = true
                        break
                    end
                end
                
                if not has_scrobbled then
                    table.insert(filtered_tracks, track)
                    seen_tracks[track_key] = true
                end
            else
                table.insert(filtered_tracks, track)
                seen_tracks[track_key] = true
            end
        end
    end
    
    return filtered_tracks
end

local function get_track_info_cached(artist, track)
    local cache_key = artist .. "|" .. track
    local now = os.time()
    
    -- Check cache first
    if cache[cache_key] and (now - cache[cache_key].time) < cache_timeout then
        return cache[cache_key].duration, cache[cache_key].playcount, cache[cache_key].artistplays
    end
    
    -- Get personal playcount
    local scrobbles_url = api.build_url(api.METHODS.USER_TRACK_SCROBBLES, {
        user = api.USERNAME,
        artist = artist,
        track = track
    })
    
    local temp_file = DATA_DIR .. "/temp_scrobbles.json"
    local temp_file_tmp = temp_file .. ".tmp"
    local cmd = string.format('"%s" -s -S -o "%s" "%s" 2>/dev/null && mv "%s" "%s"', curl, temp_file_tmp, scrobbles_url, temp_file_tmp, temp_file)
    
    local personal_playcount = "-"
    if exec_ok(cmd) then
        local f = io.open(temp_file, "r")
        if f then
            local content = f:read("*a")
            f:close()
            local data = json_decode(content)
            if data and data.trackscrobbles and data.trackscrobbles["@attr"] then
                local total = tonumber(data.trackscrobbles["@attr"]["total"]) or 0
                personal_playcount = total > 0 and tostring(total) or "-"
            end
        end
    end
    
    -- Get artist plays (user's total scrobbles for this artist)
    local artist_url = api.build_url(api.METHODS.ARTIST_INFO, {
        artist = artist,
        username = api.USERNAME
    })
    
    local artist_plays = "-"
    local temp_artist_file = DATA_DIR .. "/temp_artist.json"
    local temp_artist_tmp = temp_artist_file .. ".tmp"
    local artist_cmd = string.format('"%s" -s -S -o "%s" "%s" 2>/dev/null && mv "%s" "%s"', curl, temp_artist_tmp, artist_url, temp_artist_tmp, temp_artist_file)
    
    if exec_ok(artist_cmd) then
        local f = io.open(temp_artist_file, "r")
        if f then
            local content = f:read("*a")
            f:close()
            local data = json_decode(content)
            if data and data.artist and data.artist.stats and data.artist.stats.userplaycount then
                local plays = tonumber(data.artist.stats.userplaycount) or 0
                artist_plays = plays > 0 and tostring(plays) or "-"
            end
        end
    end
    
    -- Get duration
    local duration_url = api.build_url(api.METHODS.TRACK_INFO, {
        artist = artist,
        track = track
    })
    
    local duration_str = "-"
    local temp_duration_file = DATA_DIR .. "/temp_duration.json"
    local temp_duration_tmp = temp_duration_file .. ".tmp"
    local duration_cmd = string.format('"%s" -s -S -o "%s" "%s" 2>/dev/null && mv "%s" "%s"', curl, temp_duration_tmp, duration_url, temp_duration_tmp, temp_duration_file)
    
    if exec_ok(duration_cmd) then
        local f = io.open(temp_duration_file, "r")
        if f then
            local content = f:read("*a")
            f:close()
            local data = json_decode(content)
            if data and data.track and data.track.duration then
                local duration = tonumber(data.track.duration) or 0
                if duration > 0 then
                    local seconds = math.floor(duration / 1000)
                    local minutes = math.floor(seconds / 60)
                    seconds = seconds % 60
                    duration_str = string.format("%d:%02d", minutes, seconds)
                end
            end
        end
    end
    
    -- Cache the result
    cache[cache_key] = {
        duration = duration_str,
        playcount = personal_playcount,
        artistplays = artist_plays,
        time = now
    }
    
    return duration_str, personal_playcount, artist_plays
end

local function download_image_if_needed(image_url, image_path)
    if not image_url or image_url == "" then 
        log("No image URL provided for " .. image_path)
        return false 
    end
    
    -- Check if we already have this exact image URL cached for this path
    local cached = image_url_cache[image_path]
    local cached_url = nil
    if type(cached) == "table" then
        cached_url = cached.url
    elseif type(cached) == "string" then
        cached_url = cached
    end

    if cached_url and cached_url == image_url then
        -- Check if the file still exists
        local f = io.open(image_path, "r")
        if f then
            f:close()
            log("Using cached image for " .. image_path)
            return true -- Use existing image
        end
    end
    
    -- Download new image
    log("Downloading new image from " .. image_url .. " to " .. image_path)
    local temp_image = image_path .. ".tmp"
    local cmd = string.format('"%s" -s -S -o "%s" "%s" 2>/dev/null && mv "%s" "%s"', curl, temp_image, image_url, temp_image, image_path)
    local success = exec_ok(cmd)
    
    if success then
        -- Cache the URL for this image path (match main loop format)
        image_url_cache[image_path] = {
            url = image_url,
            track_key = ""
        }
        log("Successfully downloaded and cached image for " .. image_path)
    else
        log("Failed to download image from " .. image_url)
    end
    
    return success
end

function conky_update_lastfm()
    -- Check for internet connectivity first
    if not check_internet() then
        log("Internet probe failed; attempting Last.fm fetch anyway")
    end
    
    if not fetch_json() then 
        log("fetch_json failed, keeping existing data")
        return 
    end
    
    local all_tracks = get_tracks()
    
    -- If no tracks returned, keep existing data (don't blank everything)
    if #all_tracks == 0 then
        log("No tracks returned, keeping existing data")
        return
    end
    
    -- Prepare all data first before updating globals
    local pending_data = {}
    local pending_status = "Not Playing"
    
    -- Check if first track is currently playing
    if all_tracks[1] then
        local first_track = all_tracks[1]
        if first_track["@attr"] and first_track["@attr"]["nowplaying"] == "true" then
            pending_status = "Now Playing"
        else
            pending_status = "Paused"
        end
    end
    
    -- PHASE 1: Parse all text data and download images to staging
    -- Small delay to let the API refresh data before fetching images
    os.execute("sleep 0.5")
    
    for i = 1, 3 do
        local t = all_tracks[i]
        if t then
            local artist = (t.artist and t.artist["#text"]) or "Unknown"
            local track = t.name or "Unknown"
            local album = (t.album and t.album["#text"]) or "Unknown"
            
            -- Get track info (cached)
            local duration, playcount, artistplays = get_track_info_cached(artist, track)
            
            pending_data[i] = {
                artist = artist,
                track = track,
                album = album,
                duration = duration or "-",
                playcount = playcount or "-",
                artistplays = artistplays or "-",
                image_path = DATA_DIR .. "/cover" .. i .. ".png"
            }
            
            -- Download image to staging now
            if t.image and #t.image > 0 then
                local image_url = t.image[#t.image]["#text"] or ""
                if image_url and image_url ~= "" then
                    pending_data[i].image_url = image_url
                    
                    -- Build a track key to detect when a different track moves into this slot
                    local track_key = artist .. "|" .. track
                    pending_data[i].track_key = track_key
                    
                    -- Check if we already have this exact image URL cached AND it's for the same track
                    local need_download = true
                    local cached = image_url_cache[pending_data[i].image_path]
                    if cached and cached.url == image_url and cached.track_key == track_key then
                        local f = io.open(pending_data[i].image_path, "r")
                        if f then
                            f:close()
                            need_download = false
                            log("Cache hit for " .. pending_data[i].image_path .. " (same track and URL)")
                        end
                    elseif cached then
                        log("Cache miss: track changed from " .. (cached.track_key or "nil") .. " to " .. track_key)
                    end
                    
                    if need_download then
                        local staging_image = DATA_DIR .. "/cover" .. i .. "_staging.png"
                        log("Downloading image to staging: " .. staging_image)
                        local cmd = string.format('"%s" -s -S -o "%s" "%s" 2>/dev/null', curl, staging_image, image_url)
                        if exec_ok(cmd) then
                            pending_data[i].staging_image = staging_image
                        end
                    end
                end
            end
        else
            -- No track at this position - keep existing data, don't overwrite with empty
            pending_data[i] = nil
        end
    end
    
    -- PHASE 2: Update text FIRST, then images
    -- Text globals need to be ready BEFORE images appear
    -- Only update if we have valid data
    _G["nowplaying_status"] = pending_status
    
    -- First, update ALL text globals (only if we have data for that slot)
    for i = 1, 3 do
        local data = pending_data[i]
        if data then
            _G["artist"..i] = data.artist or ""
            _G["track"..i] = data.track or ""
            _G["album"..i] = data.album or ""
            _G["duration"..i] = data.duration or "-"
            _G["playcount"..i] = data.playcount or "-"
            _G["artistplays"..i] = data.artistplays or "-"
            log(string.format("Updated track %d: %s - %s", i, data.artist, data.track))
        else
            log(string.format("No new data for track %d, keeping existing", i))
        end
    end
    
    -- Then, move ALL images to final locations
    local cache_updated = false
    for i = 1, 3 do
        local data = pending_data[i]
        if data and data.staging_image then
            local mv_cmd = string.format('mv "%s" "%s" 2>/dev/null', data.staging_image, data.image_path)
            if exec_ok(mv_cmd) then
                -- Store both URL and track_key so we can detect track changes
                image_url_cache[data.image_path] = {
                    url = data.image_url,
                    track_key = data.track_key
                }
                cache_updated = true
                log("Moved staging image to: " .. data.image_path)
            end
        end
    end
    
    -- Persist the cache to disk if it changed
    if cache_updated then
        save_image_cache()
    end
end

-- Create conky functions
for i = 1, 3 do
    _G["conky_artist"..i] = function() return _G["artist"..i] end
    _G["conky_track"..i] = function() return _G["track"..i] end
    _G["conky_album"..i] = function() return _G["album"..i] end
    _G["conky_duration"..i] = function() return _G["duration"..i] end
    _G["conky_playcount"..i] = function() return _G["playcount"..i] end
    _G["conky_artistplays"..i] = function() return _G["artistplays"..i] end
end

function conky_nowplaying1()
    local status = _G["nowplaying_status"]
    
    if status == "Now Playing" then
        return "▶ Playing"
    elseif status == "Paused" then
        return "I I Paused"
    else
        return ""  -- Return empty string when not playing
    end
end
