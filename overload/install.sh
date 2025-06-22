#!/bin/bash

# Conky Last.fm Panel - Dependency Installation Script for Arch Linux
# This script installs all required dependencies for the Last.fm panel

set -e  # Exit on any error

echo "🎵 Installing Conky Last.fm Panel Dependencies for Arch Linux..."
echo "================================================================="

# Function to check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        echo "❌ This script should not be run as root!"
        echo "   Run it as a regular user - it will use sudo when needed."
        exit 1
    fi
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install AUR helper if needed
install_aur_helper() {
    if ! command_exists yay && ! command_exists paru; then
        echo "📦 Installing yay (AUR helper)..."
        sudo pacman -S --needed base-devel git
        cd /tmp
        git clone https://aur.archlinux.org/yay.git
        cd yay
        makepkg -si --noconfirm
        cd "$OLDPWD"
        echo "✅ yay installed successfully"
    else
        echo "✅ AUR helper already installed"
    fi
}

check_root

# Update system
echo "📦 Updating system packages..."
sudo pacman -Syu --noconfirm

# Install core packages
echo "🔧 Installing core system packages..."
sudo pacman -S --needed --noconfirm \
    conky \
    lua \
    curl \
    cairo \
    lua-lgi \
    imagemagick \
    imlib2 \
    jq \
    file \
    luarocks

echo "✅ Core packages installed successfully"

# Install AUR helper and optional packages
install_aur_helper

# Install optional AUR packages
echo "🔧 Installing optional AUR packages..."
if command_exists yay; then
    AUR_HELPER="yay"
elif command_exists paru; then
    AUR_HELPER="paru"
fi

if [[ -n "$AUR_HELPER" ]]; then
    echo "Using $AUR_HELPER for AUR packages..."
    # $AUR_HELPER -S --noconfirm lua-cairo  # Optional alternative Cairo bindings
    echo "✅ AUR packages ready (install manually if needed)"
else
    echo "⚠️  No AUR helper available for optional packages"
fi

# Install Lua packages
echo "🌙 Installing Lua packages..."
sudo luarocks install dkjson

# Verify installations
echo "✅ Verifying installations..."

# Check Conky
if command_exists conky; then
    echo "  ✓ Conky: $(conky --version | head -n1)"
else
    echo "  ✗ Conky: Not found"
    exit 1
fi

# Check Lua
if command_exists lua; then
    echo "  ✓ Lua: $(lua -v 2>&1 | head -n1)"
else
    echo "  ✗ Lua: Not found"
    exit 1
fi

# Check curl
if command_exists curl; then
    echo "  ✓ curl: $(curl --version | head -n1)"
else
    echo "  ✗ curl: Not found"
    exit 1
fi

# Check ImageMagick
if command_exists convert; then
    echo "  ✓ ImageMagick: $(convert --version | head -n1)"
else
    echo "  ✗ ImageMagick: Not found"
    exit 1
fi

# Check Cairo
if pkg-config --exists cairo; then
    echo "  ✓ Cairo: $(pkg-config --modversion cairo)"
else
    echo "  ✗ Cairo: Not found"
    exit 1
fi

# Check dkjson
if lua -e "require('dkjson')" 2>/dev/null; then
    echo "  ✓ dkjson: Available"
else
    echo "  ✗ dkjson: Not found"
    exit 1
fi

# Check lua-lgi
if lua -e "require('lgi')" 2>/dev/null; then
    echo "  ✓ lua-lgi: Available"
else
    echo "  ⚠️  lua-lgi: Not found (optional for advanced Cairo features)"
fi

echo ""
echo "🎉 All dependencies installed successfully!"
echo ""
echo "📋 Next steps:"
echo "   1. Configure your Last.fm API key in the Lua script"
echo "   2. Set your Last.fm username in the script"
echo "   3. Run: conky -c 'lastfm panel'"
echo ""
echo "📁 Files created:"
echo "   - dependencies.txt  (list of required packages)"
echo "   - install_dependencies.sh  (this installation script)"
echo ""
echo "🔧 To manually install any missing packages:"
echo "   sudo pacman -S <package-name>"
echo "   luarocks install <lua-package>"
echo ""
