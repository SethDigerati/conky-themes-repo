# Conky Themes & Widgets

A collection of modern, beautiful Conky themes and widgets for Linux desktops.

![GitHub repo size](https://img.shields.io/github/repo-size/SethDigerati/conky-themes-repo)
![GitHub license](https://img.shields.io/github/license/SethDigerati/conky-themes-repo)
![GitHub stars](https://img.shields.io/github/stars/SethDigerati/conky-themes-repo)

## Available Themes

### Overload - System Monitor

![Overload Preview](overload/assets/overload_example.png)
![Right Preview](overload/assets/example1.png)
![Left Preview](overload/assets/example2.png)

**Features:**

- Multi-core CPU monitoring
- Memory & network statistics  
- Process information
- Clean, modern design
- Zero dependencies beyond Conky

---

### LastFM - Music Display

![LastFM Preview](lastfm/assets/lastfm_example.png)

**Features:**

- Real-time Last.fm integration

- Album artwork display
- Personal play statistics
- Track duration & info
- Fully portable design

---

## Quick Start

### Option 1: Clone Everything

```bash
git clone https://github.com/SethDigerati/conky-themes-repo.git
cd conky-themes-repo
```

### Option 2: Download Individual Themes

```bash
# Just the system monitor
git clone --depth 1 --filter=blob:none --sparse https://github.com/SethDigerati/conky-themes-repo.git
cd conky-themes-repo
git sparse-checkout set overload

# Just the music theme
git sparse-checkout set lastfm
```

### Running Themes

```bash
# Overload (System Monitor)
conky -c overload/cpu.conf

# Other Overload modules
conky -c overload/gpu.conf
conky -c overload/network.conf
conky -c overload/storage.conf
conky -c overload/weather.conf

# Last.fm (Music)
conky -c lastfm/lastfm.conf
```

### Last.fm API Credentials

Copy [.env.template](.env.template) to `api.env` (preferred) or `.env`, then set:

- `LASTFM_API_KEY`
- `LASTFM_USERNAME`

Do not commit your credentials.

## Requirements

### Universal Requirements

- **Linux**
- **Conky** (X11-based; on Sway/Wayland you typically run Conky via XWayland)

### Theme-Specific Requirements

| Theme        | Additional Requirements                  |
|--------------|------------------------------------------|
| **Overload** | None                                     |
| **LastFM**   | `curl`, `lua-dkjson`, Last.fm API key    |

### Installation Commands

```bash
# Ubuntu/Debian
sudo apt install conky-all curl lua-dkjson

# Arch Linux
sudo pacman -S conky curl lua-dkjson

# Fedora
sudo dnf install conky curl lua-dkjson
```

## Theme Comparison

| Feature            | Overload          | LastFM        |
|--------------------|-------------------|---------------|
| **Purpose**        | System monitoring | Music display |
| **Complexity**     | Simple            | Moderate      |
| **Dependencies**   | Conky only        | Conky + API   |
| **Network**        | No                | Yes           |
| **Setup Time**     | 2 minutes         | 5 minutes     |
| **Customization**  | High              | High          |
| **Resource Usage** | Minimal           | Minimal       |

## Repository Structure

```text
conky-themes-repo/
├── README.md                # This file
├── LICENSE                  # MIT License
├── .env.template            # API credentials template
├── api.env                  # API credentials (keep untracked/private)
├── config/
│   └── api-config.lua        # Loads api.env/.env and exposes API config
├── overload/                 # System monitor configs
│   ├── cpu.conf
│   ├── gpu.conf
│   ├── network.conf
│   ├── storage.conf
│   ├── weather.conf
│   ├── network.lua
│   ├── weather.lua
│   └── assets/               # Screenshots & resources
└── lastfm/
    ├── lastfm.conf           # Conky config
    ├── lastfm.lua            # Last.fm API logic
    └── assets/               # Screenshot(s)
```

## Contributing

Contributions are welcome! Here's how:

1. **Fork** the repository
2. **Create** a feature branch (`git checkout -b feature/amazing-theme`)
3. **Commit** your changes (`git commit -m 'Add amazing theme'`)
4. **Push** to the branch (`git push origin feature/amazing-theme`)
5. **Open** a Pull Request

### Contribution Ideas

- New themes
- Widget components
- Bug fixes
- Documentation improvements
- Performance optimizations

## Features Roadmap

### Planned Themes

- Weather widget
- Cryptocurrency tracker
- Network monitor (in development)
- Disk usage analyzer (in development)

### Planned Features

- Theme manager script
- Auto-updater

## License

This project is licensed under the **MIT License** - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- **[Conky Team](https://github.com/brndnmtthws/conky)** - For the amazing system monitor
- **[TeejeeTech](http://teejeetech.blogspot.in/)** - Original Overload theme inspiration  
- **[Last.fm](https://last.fm)** - For the music tracking API
- **Linux Community** - For continuous support and feedback

## Support

- **Bug Reports**: [GitHub Issues](https://github.com/SethDigerati/conky-themes-repo/issues)
- **Discussions**: [GitHub Discussions](https://github.com/SethDigerati/conky-themes-repo/discussions)
- **Email**: <sethodhiambojad@gmail.com>
