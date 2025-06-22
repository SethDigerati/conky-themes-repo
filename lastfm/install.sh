#!/bin/bash
# Last.fm Theme Installation Script
# Makes the theme portable and easy to set up

set -e

THEME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "Installing Last.fm Conky Theme from: $THEME_DIR"

# Check if running from correct directory
if [ ! -f "$THEME_DIR/lastfm.lua" ]; then
    echo "Error: Please run this script from the lastfm directory"
    exit 1
fi

# Check dependencies
echo "Checking dependencies..."

if ! command -v conky &> /dev/null; then
    echo "Error: Conky is not installed. Please install it first:"
    echo "  Ubuntu/Debian: sudo apt install conky-all"
    echo "  Arch Linux: sudo pacman -S conky"
    echo "  Fedora: sudo dnf install conky"
    exit 1
fi

if ! command -v curl &> /dev/null; then
    echo "Error: curl is not installed. Please install it first:"
    echo "  Ubuntu/Debian: sudo apt install curl"
    echo "  Arch Linux: sudo pacman -S curl"
    echo "  Fedora: sudo dnf install curl"
    exit 1
fi

if ! lua -e "require('dkjson')" &> /dev/null; then
    echo "Error: lua-dkjson is not installed. Please install it first:"
    echo "  Ubuntu/Debian: sudo apt install lua-dkjson"
    echo "  Arch Linux: sudo pacman -S lua-dkjson"
    echo "  Fedora: sudo dnf install lua-dkjson"
    exit 1
fi

echo "✓ All dependencies found"

# Create assets directory
mkdir -p "$THEME_DIR/assets"
echo "✓ Created assets directory"

# Set up API configuration
if [ ! -f "$THEME_DIR/api_config.lua" ]; then
    if [ -f "$THEME_DIR/api_config.lua.template" ]; then
        cp "$THEME_DIR/api_config.lua.template" "$THEME_DIR/api_config.lua"
        echo "✓ Created api_config.lua from template"
        echo ""
        echo "IMPORTANT: You need to edit api_config.lua with your Last.fm credentials:"
        echo "  1. Get your API key from: https://www.last.fm/api/account/create"
        echo "  2. Edit $THEME_DIR/api_config.lua"
        echo "  3. Replace YOUR_API_KEY_HERE with your actual API key"
        echo "  4. Replace YOUR_LASTFM_USERNAME_HERE with your username"
        echo ""
        echo "After editing the config file, run the theme with:"
        echo "  conky -c \"$THEME_DIR/lastfm panel\""
    else
        echo "Error: api_config.lua.template not found"
        exit 1
    fi
else
    echo "✓ api_config.lua already exists"
    echo ""
    echo "To run the theme:"
    echo "  conky -c \"$THEME_DIR/lastfm panel\""
fi

echo ""
echo "Installation complete! 🎵"
