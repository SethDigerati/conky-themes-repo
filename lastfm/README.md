# Last.fm - Music Conky Theme

A beautiful Conky theme that displays your Last.fm listening activity with real-time updates, album artwork, and detailed track information.

![Last.fm Theme Preview](assets/lastfm_example.png)

## ✨ Features

- **Fully Portable** - Works from any directory, no hardcoded paths
- **Real-time Last.fm Integration** - Shows your currently playing and recently scrobbled tracks
- **Album Artwork Display** - High-quality album covers downloaded automatically
- **Personal Statistics** - Your personal play counts (not global stats)
- **Track Duration** - Displays track length in MM:SS format
- **Smart Duplicate Filtering** - Prevents "now playing" tracks from appearing twice
- **Optimized Performance** - Fast, efficient API calls and caching
- **PNG Image Support** - High-quality album artwork
- **Clean Music UI** - Designed specifically for music lovers
- **Easy Setup** - Automated installation script

## 📸 Screenshot

![Last.fm Music Display](assets/lastfm_example.png)
*Beautiful music display with album art, track info, and personal statistics*

## 🚀 Quick Start

### Prerequisites

- **Conky** - System monitor for X11
- **curl** - For API requests
- **lua** with **dkjson** module - JSON parsing
- **Last.fm Account** - For API access

### Installation

1. **Download/Clone the theme:**
   ```bash
   # Option 1: Clone to any directory
   git clone <repository-url> ~/my-conky-themes
   cd ~/my-conky-themes/lastfm
   
   # Option 2: Download and extract to any location
   # The theme is fully portable!
   ```

2. **Run the installation script:**
   ```bash
   ./install.sh
   ```
   This will:
   - Check all dependencies
   - Create necessary directories
   - Set up the API configuration template
   - Provide setup instructions

3. **Configure your Last.fm credentials:**
   - Get your API key from [Last.fm API Account Creation](https://www.last.fm/api/account/create)
   - Edit `api_config.lua` and replace:
     - `YOUR_API_KEY_HERE` with your actual API key
     - `YOUR_LASTFM_USERNAME_HERE` with your Last.fm username

4. **Run the theme:**
   ```bash
   conky -c "lastfm panel"
   ```
   
   Or with full path from anywhere:
   ```bash
   conky -c "/path/to/lastfm/lastfm panel"
   ```

## ⚙️ Configuration

### Theme Customization

Edit the `lastfm panel` file to customize:

- **Position**: Change `alignment`, `gap_x`, `gap_y`
- **Size**: Modify `minimum_size`, `maximum_width`
- **Colors**: Update `color0`, `color1`, `color2`, etc.
- **Fonts**: Change `xftfont` settings
- **Transparency**: Adjust `own_window_argb_value`

### API Settings

The `api_config.lua` file contains:
- API credentials (your API key and username)
- Rate limiting settings
- Cache configuration

## 📁 File Structure

```
lastfm/
├── lastfm panel         # Main Conky configuration
├── lastfm.lua          # Core script logic
├── api_config.lua.template  # Template for API setup
├── LICENSE             # License file
└── assets/
    ├── lastfm_example.png   # Theme screenshot
    ├── cover1.png          # Album artwork (auto-generated)
    ├── cover2.png          # Album artwork (auto-generated)
    ├── cover3.png          # Album artwork (auto-generated)
    ├── raw.json           # API response cache
    └── debug.log          # Debug information
```

## 🔧 Technical Details

### Portability Features

The theme is designed to be fully portable:

- **Relative Paths** - All file references use relative paths
- **Auto-Detection** - Script automatically detects its location
- **No Hardcoded Directories** - Works from any folder location
- **Self-Contained** - All assets stored within theme directory

### Usage Examples

```bash
# Works from anywhere
cd ~/Downloads/lastfm && conky -c "lastfm panel"

# Or with full path
conky -c "/any/path/to/lastfm/lastfm panel"

# Multiple instances from different locations
conky -c ~/themes/music/lastfm/"lastfm panel" &
conky -c /opt/conky-themes/lastfm/"lastfm panel" &
```

### API Endpoints Used

- `user.getrecenttracks` - Recent listening history
- `track.getInfo` - Track duration and metadata
- `user.getTrackScrobbles` - Personal play counts

### Performance Optimizations

- **Efficient Caching** - Reduces API calls
- **Smart Image Downloads** - Only downloads when album changes
- **Optimized JSON Parsing** - Fast data processing
- **Duplicate Prevention** - Filters redundant tracks

### Data Flow

1. Fetch recent tracks from Last.fm API
2. Filter duplicates and process track data
3. Download album artwork if needed
4. Get personal play counts and track duration
5. Update Conky display variables

## 🎨 Customization Examples

### Color Schemes

**Orange Accent** (default):
```bash
color0 white          # Primary text
color1 EAEAEA         # Secondary text
color2 FFA300         # Accent color
```

**Blue Theme**:
```bash
color0 white
color1 EAEAEA
color2 0099FF
```

**Green Theme**:
```bash
color0 white
color1 EAEAEA
color2 00CC66
```

## 🐛 Troubleshooting

### Common Issues

**No tracks showing:**
```bash
# Check API credentials
cat ~/.conky/lastfm/api_config.lua

# Check debug log
tail -f ~/.conky/lastfm/assets/debug.log
```

**Images not loading:**
```bash
# Verify image files exist
ls -la ~/.conky/lastfm/assets/*.png

# Check curl installation
which curl
```

**API errors:**
```bash
# Test API connectivity
curl "https://ws.audioscrobbler.com/2.0/?method=user.getrecenttracks&user=YOUR_USERNAME&api_key=YOUR_API_KEY&format=json&limit=1"
```

### Debug Mode

View logs in real-time:
```bash
tail -f ~/.conky/lastfm/assets/debug.log
```

### Performance Issues

If the theme is slow:
1. Check your internet connection
2. Verify API rate limits aren't exceeded
3. Clear cache files: `rm ~/.conky/lastfm/assets/*.json`
4. Restart Conky

## 🔒 Privacy & Security

- **API credentials** are stored locally in `api_config.lua`
- **No personal data** is transmitted except to Last.fm
- **Local caching** minimizes API requests
- **Open source** - all code is auditable

## 📊 System Requirements

- **OS**: Linux with X11
- **RAM**: ~10MB additional usage
- **CPU**: Minimal impact
- **Network**: Periodic API calls (~1KB/update)
- **Disk**: ~5MB for cache and images

## 🎵 Music Integration

### Supported Players

The theme works with any music player that scrobbles to Last.fm:

- **Spotify** (with Last.fm scrobbling enabled)
- **Music Player Daemon (MPD)**
- **VLC Media Player**
- **Audacious**
- **Clementine**
- **And many more!**

### Last.fm Setup

1. Create a Last.fm account at [last.fm](https://last.fm)
2. Connect your music player to Last.fm
3. Enable scrobbling in your player settings
4. Get API credentials for this theme

## 🤝 Contributing

Contributions are welcome! Areas for improvement:

- Additional music services (Spotify API, etc.)
- New layout designs
- Enhanced album artwork handling
- Performance optimizations

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🙏 Acknowledgments

- **Last.fm** - For the excellent music tracking API
- **Conky** - For the flexible system monitoring framework
- **dkjson** - For reliable JSON parsing in Lua
- **Music Community** - For inspiration and feedback

---

*Made with ❤️ for music lovers and Linux enthusiasts*
