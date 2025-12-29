local json = require("dkjson")
local api = require("api_config")

-- CONFIG - Using XDG_RUNTIME_DIR for caching
local XDG_RUNTIME_DIR = os.getenv("XDG_RUNTIME_DIR") or "/tmp"
local DATA_DIR = XDG_RUNTIME_DIR .. "/lastfm"
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
log("Starting Last.fm script, caching to: " .. DATA_DIR)

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
local image_url_cache = {}

local function fetch_json()
    local url = api.build_url(api.METHODS.RECENT_TRACKS, {
        user = api.USERNAME,
        limit = 5
    })
    
    local temp_raw = RAW_JSON .. ".tmp"
    local cmd = string.format('%s -s -S -o "%s" "%s" 2>/dev/null && mv "%s" "%s"', curl, temp_raw, url, temp_raw, RAW_JSON)
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
    local cmd = string.format('%s -s -S -o "%s" "%s" 2>/dev/null && mv "%s" "%s"', curl, temp_file_tmp, scrobbles_url, temp_file_tmp, temp_file)
    
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
    end
    
    -- Get artist plays (user's total scrobbles for this artist)
    local artist_url = api.build_url(api.METHODS.ARTIST_INFO, {
        artist = artist,
        username = api.USERNAME
    })
    
    local artist_plays = "-"
    local temp_artist_file = DATA_DIR .. "/temp_artist.json"
    local temp_artist_tmp = temp_artist_file .. ".tmp"
    local artist_cmd = string.format('%s -s -S -o "%s" "%s" 2>/dev/null && mv "%s" "%s"', curl, temp_artist_tmp, artist_url, temp_artist_tmp, temp_artist_file)
    
    if os.execute(artist_cmd) then
        local f = io.open(temp_artist_file, "r")
        if f then
            local content = f:read("*a")
            f:close()
            local data = json.decode(content)
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
    local duration_cmd = string.format('%s -s -S -o "%s" "%s" 2>/dev/null && mv "%s" "%s"', curl, temp_duration_tmp, duration_url, temp_duration_tmp, temp_duration_file)
    
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
    local temp_image = image_path .. ".tmp"
    local cmd = string.format('%s -s -S -o "%s" "%s" 2>/dev/null && mv "%s" "%s"', curl, temp_image, image_url, temp_image, image_path)
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
                    
                    -- Check if we already have this exact image URL cached
                    local need_download = true
                    if image_url_cache[pending_data[i].image_path] == image_url then
                        local f = io.open(pending_data[i].image_path, "r")
                        if f then
                            f:close()
                            need_download = false
                        end
                    end
                    
                    if need_download then
                        local staging_image = DATA_DIR .. "/cover" .. i .. "_staging.png"
                        log("Downloading image to staging: " .. staging_image)
                        local cmd = string.format('%s -s -S -o "%s" "%s" 2>/dev/null', curl, staging_image, image_url)
                        if os.execute(cmd) then
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
    for i = 1, 3 do
        local data = pending_data[i]
        if data and data.staging_image then
            local mv_cmd = string.format('mv "%s" "%s" 2>/dev/null', data.staging_image, data.image_path)
            if os.execute(mv_cmd) then
                image_url_cache[data.image_path] = data.image_url
                log("Moved staging image to: " .. data.image_path)
            end
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
    _G["conky_artistplays"..i] = function() return _G["artistplays"..i] end
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
