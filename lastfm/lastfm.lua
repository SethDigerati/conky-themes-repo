local json = require("dkjson")
local api = require("api_config")

-- CONFIG - Using relative paths for portability
local SCRIPT_DIR = debug.getinfo(1).source:match("@(.*/)") or "./"
local DATA_DIR = SCRIPT_DIR .. "assets"
local RAW_JSON = DATA_DIR .. "/raw.json"
local LOG_FILE = DATA_DIR .. "/debug.log"
local curl = "/usr/bin/curl"

-- Logger function
local function log(message)
    local f = io.open(LOG_FILE, "a")
    if f then
        f:write(os.date("[%Y-%m-%d %H:%M:%S] ") .. tostring(message) .. "\n")
        f:close()
    end
end

-- Create assets dir
local mkdir_result = os.execute("mkdir -p " .. DATA_DIR)
if not mkdir_result then
    log("Failed to create directory: " .. DATA_DIR)
end
log("Starting Last.fm script from: " .. SCRIPT_DIR)

-- Initialize global variables
for i = 1, 3 do
    _G["artist"..i] = ""
    _G["track"..i] = ""
    _G["album"..i] = ""
    _G["duration"..i] = "-"
    _G["playcount"..i] = "-"
end

-- Add global variable for now playing status
_G["nowplaying_status"] = "Not Playing"

-- Cache for API calls to avoid repeated requests
local cache = {}
local cache_timeout = 30 -- seconds

-- Cache for image URLs to avoid re-downloading the same image
local image_url_cache = {}

local function fetch_json()
    local url = api.build_url(api.METHODS.RECENT_TRACKS, {
        user = api.USERNAME,
        limit = 5
    })
    
    local cmd = string.format('%s -s -S -o "%s" "%s" 2>/dev/null', curl, RAW_JSON, url)
    return os.execute(cmd)
end

local function get_tracks()
    local f = io.open(RAW_JSON, "r")
    if not f then return {} end
    
    local content = f:read("*a")
    f:close()
    
    local data = json.decode(content)
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
        return cache[cache_key].duration, cache[cache_key].playcount
    end
    
    -- Get personal playcount
    local scrobbles_url = api.build_url(api.METHODS.USER_TRACK_SCROBBLES, {
        user = api.USERNAME,
        artist = artist,
        track = track
    })
    
    local temp_file = DATA_DIR .. "/temp_scrobbles.json"
    local cmd = string.format('%s -s -S -o "%s" "%s" 2>/dev/null', curl, temp_file, scrobbles_url)
    
    local personal_playcount = "-"
    if os.execute(cmd) then
        local f = io.open(temp_file, "r")
        if f then
            local content = f:read("*a")
            f:close()
            local data = json.decode(content)
            if data and data.trackscrobbles and data.trackscrobbles["@attr"] then
                local total = tonumber(data.trackscrobbles["@attr"]["total"]) or 0
                personal_playcount = total > 0 and tostring(total) or "-"
            end
        end
        os.remove(temp_file)
    end
    
    -- Get duration
    local duration_url = api.build_url(api.METHODS.TRACK_INFO, {
        artist = artist,
        track = track
    })
    
    local duration_str = "-"
    local temp_duration_file = DATA_DIR .. "/temp_duration.json"
    local duration_cmd = string.format('%s -s -S -o "%s" "%s" 2>/dev/null', curl, temp_duration_file, duration_url)
    
    if os.execute(duration_cmd) then
        local f = io.open(temp_duration_file, "r")
        if f then
            local content = f:read("*a")
            f:close()
            local data = json.decode(content)
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
        os.remove(temp_duration_file)
    end
    
    -- Cache the result
    cache[cache_key] = {
        duration = duration_str,
        playcount = personal_playcount,
        time = now
    }
    
    return duration_str, personal_playcount
end

local function download_image_if_needed(image_url, image_path)
    if not image_url or image_url == "" then 
        log("No image URL provided for " .. image_path)
        return false 
    end
    
    -- Check if we already have this exact image URL cached for this path
    if image_url_cache[image_path] == image_url then
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
    local cmd = string.format('%s -s -S -o "%s" "%s" 2>/dev/null', curl, image_path, image_url)
    local success = os.execute(cmd)
    
    if success then
        -- Cache the URL for this image path
        image_url_cache[image_path] = image_url
        log("Successfully downloaded and cached image for " .. image_path)
    else
        log("Failed to download image from " .. image_url)
    end
    
    return success
end

function conky_update_lastfm()
    if not fetch_json() then return end
    
    local all_tracks = get_tracks()
    
    -- Check if first track is currently playing
    if all_tracks[1] then
        local first_track = all_tracks[1]
        if first_track["@attr"] and first_track["@attr"]["nowplaying"] == "true" then
            _G["nowplaying_status"] = "Now Playing"
        else
            _G["nowplaying_status"] = "Paused"
        end
    else
        _G["nowplaying_status"] = "Not Playing"
    end
    
    for i = 1, 3 do
        local t = all_tracks[i]
        if t then
            local artist = (t.artist and t.artist["#text"]) or "Unknown"
            local track = t.name or "Unknown"
            local album = (t.album and t.album["#text"]) or "Unknown"
            local image_path = DATA_DIR .. "/cover" .. i .. ".png"
            
            -- Get album art
            if t.image and #t.image > 0 then
                local image_url = t.image[#t.image]["#text"] or ""
                download_image_if_needed(image_url, image_path)
            end
            
            -- Get track info (cached)
            local duration, playcount = get_track_info_cached(artist, track)
            
            _G["artist"..i] = artist
            _G["track"..i] = track
            _G["album"..i] = album
            _G["duration"..i] = duration or "-"
            _G["playcount"..i] = playcount or "-"
        else
            _G["artist"..i] = ""
            _G["track"..i] = ""
            _G["album"..i] = ""
            _G["duration"..i] = "-"
            _G["playcount"..i] = "-"
        end
    end
end

-- Create conky functions
for i = 1, 3 do
    _G["conky_artist"..i] = function() return _G["artist"..i] end
    _G["conky_track"..i] = function() return _G["track"..i] end
    _G["conky_album"..i] = function() return _G["album"..i] end
    _G["conky_duration"..i] = function() return _G["duration"..i] end
    _G["conky_playcount"..i] = function() return _G["playcount"..i] end
end

function conky_nowplaying1()
    local status = _G["nowplaying_status"]
    
    if status == "Now Playing" then
        return "▶ Playing"
    elseif status == "Paused" then
        return "I I Paused"
    else
        return "something"  -- Return empty string when not playing
    end
end
