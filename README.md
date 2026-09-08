<div align="center">

# 💀 MIDNIGHT-DOLL // CYBERDECK HUD
### *A Retro-Cyberpunk Dual-Bar HUD & Desktop Suite for Omarchy / Hyprland*

[![Platform](https://img.shields.io/badge/Platform-Linux%20%7C%20Hyprland-ff51c5?style=flat-square)](#)
[![Engine](https://img.shields.io/badge/Engine-Quickshell-bb9af7?style=flat-square)](#)
[![Theme](https://img.shields.io/badge/Theme-Midnight--Doll-ff51c5?style=flat-square)](#)
[![License](https://img.shields.io/badge/License-MIT-white?style=flat-square)](#)

```text
  __  __ _     _       _       _     _         ____        _ _ 
 |  \/  (_) __| |_ __ (_) __ _| |__ | |_      |  _ \  ___ | | |
 | |\/| | |/ _` | '_ \| |/ _` | '_ \| __|_____| | | |/ _ \| | |
 | |  | | | (_| | | | | | (_| | | | | |_|_____| |_| | (_) | | |
 |_|  |_|_|\__,_|_| |_|_|\__, |_| |_|\__|     |____/ \___/|_|_|
                         |___/      // CYBERDECK HUD
```

*Ultra-dense, claustrophobic, retro-futuristic hacker cyberdeck interface featuring custom audio visualizers, live telemetry, dual-bar sequencing, and solid pitch-black aesthetics.*

</div>

---

## ⚡ Key Features

- 💀 **Cyberdeck Skull Menu Launcher**: Dedicated **18px Neon Pink Nerd Font Skull (`󰚌`)** menu icon on the top bar with full native integration with the official Omarchy application launcher and shell menus.
- 🎛️ **Dual-Bar Sequencing Architecture**:
  - **Top Bar (30px)**: Full-width priority header with solid pitch-black `#010101` backplane and neon accent underline.
  - **Left Launcher Panel (36px)**: Edge-flush vertical app launcher with interactive right-click JSON shortcut editor.
  - **Pixel-Perfect Curved Seam**: Anti-aliased QML Canvas connecting the top and left bars without graphical tearing across scaled displays.
- 📊 **Real-Time Ultra-Fast System Telemetry & Interactive HUD**: Custom 3ms metrics sampler monitoring **CPU %**, **RAM (Used / Total)**, **Disk %**, and **Live Network TX / RX** rates. The HUD title is fully interactive: click the accent header/subtitle to instantly summon a floating **btop** activity monitor or your own custom command. Supports dual-tone (`TITLE // SUBTITLE`) or single-word accent branding (e.g. `ro0tUser`).
- 🎵 **Violet LED Dot-Matrix Audio Visualizer**:
  - Pipewire-driven **CAVA spectrum capture**.
  - **22-column × 5-tier discrete violet LED dot-matrix** (`#bb9af7`) with **neon pink peak indicators** (`#ff51c5`).
  - **Inverted Stacked Audio Gauges**: Pinched `AIR` (top), `MID` (middle), and `BASS` (bottom) level meters.
- 📟 **Bracketed Workspaces**: Retro `[1] [2] [3] [4] [5]` workspace switcher with neon pink active pill fill and inverted black typography.
- 🕒 **Military Monospace Header Clock**: `[ MMM DD YYYY / DDDD / HHMM ]` format centered on the top bar.
- 🔒 **Total Theme Isolation**: Zero style leak. Switching to standard Omarchy themes (e.g. *Kanagawa*, *Catppuccin*) instantly unloads the left bar, HUD, and custom visualizer, reverting 100% cleanly to stock settings.

---

## 📦 File Tree Structure

```text
midnight-doll-dots/
├── README.md                      # Documentation & showcase
├── install.sh                     # Automated 1-click installer & backup generator
├── uninstall.sh                   # Instant rollback script
├── config/
│   └── omarchy/
│       ├── sys-hud.sh             # Fast real-time system metrics engine
│       ├── cava.conf              # Audio spectrum capture profile
│       ├── midnight-shortcuts.json# Left bar launcher shortcuts store
│       └── themes/
│           └── midnight-doll/     # Colors, Hyprland rules, and terminal profiles
│               ├── colors.toml
│               ├── hyprland.lua
│               └── ghostty.conf
└── shell-patch/
    └── plugins/
        ├── bar/
        │   ├── Bar.qml            # Dual-bar HUD & visualizer core engine
        │   └── widgets/
        │       └── Workspaces.qml # Bracketed [1] [2] workspaces
        └── panels/clock/
            └── BarWidget.qml      # Military uppercase date-time widget
```

---

## 🚀 Quick Start & Installation

### 1. Requirements
Ensure the following tools and fonts are installed on your system:
- **Omarchy Shell** / **Quickshell**
- **Hyprland**
- **cava** (for audio visualizer: `sudo pacman -S cava`)
- **pipewire**
- **JetBrainsMono Nerd Font** (or `ttf-jetbrains-mono-nerd`)

### 2. Install
Clone the repository and run the automated installer:

```bash
git clone https://github.com/PunchManSam/midnight-doll-dots.git
cd midnight-doll-dots
chmod +x install.sh
./install.sh
```

The interactive installer will guide you through configuration steps:
1. **CAVA Visualizer**: Checks if `cava` is installed, offering 1-click automatic installation if missing.
2. **Dual-Tone Accent Colors**: Configure your **Primary Accent** (active workspaces, buttons, peak LEDs, window borders) and **Complimentary Accent** (HUD title, telemetry metrics, visualizer LEDs). Features smart recommended pairings for every primary color, a full palette of complimentary options, or custom hex codes.
3. **HUD Header Text**: Set custom top-bar title and subtitle (e.g. `MIDNIGHT-DOLL // HUD` or single handle like `ro0tUser`).
4. **HUD Click Action**: Configure the command executed when clicking the HUD title/subtitle (Default: floating `btop` system monitor via `omarchy-launch-or-focus-tui btop`).
5. **Omarchy Menu Icon**: Set a custom launcher icon glyph from [Nerd Fonts](https://www.nerdfonts.com/cheat-sheet) (Default: `󰚌`).

After configuration, the installer will:
1. Automatically create a timestamped backup in `~/.config/omarchy/backups/`.
2. Deploy the theme, scripts, and user plugins.
3. Activate **Midnight-Doll** and reload your shell live.

---

## 🛠️ Customization

### Left Bar App Shortcuts
Edit `~/.config/omarchy/midnight-shortcuts.json` or simply **Right-Click** anywhere on the Left Bar to open the graphical in-bar shortcut editor!

```json
[
  { "glyph": "󰈹", "command": "firefox" },
  { "glyph": "󰨞", "command": "code" },
  { "glyph": "󰋋", "command": "spotify" },
  { "glyph": "󰉋", "command": "nautilus" },
  { "glyph": "󰞷", "command": "discord" }
]
```

### Color Palette
Dual-tone colors are configured during installation or in `~/.config/omarchy/themes/midnight-doll/colors.toml`:
- **Background**: `#010101` (Pitch Black)
- **Primary Accent**: `#ff51c5` (Cyberpunk Pink default — workspaces, peak LEDs, window borders)
- **Complimentary Accent**: `#bb9af7` (Glowing Violet default — HUD title, metrics, active LED matrix)
- **Urgent / Warning**: `#ff5555`

---

## 🔄 Uninstallation & Rollback

To restore your pre-Midnight-Doll configuration:

```bash
cd midnight-doll-dots
./uninstall.sh
```

---

## ⚠️ Disclaimer

> [!WARNING]
> This project, scripts, and configuration files are provided **"AS IS"** without warranty of any kind, express or implied. Execute and install this software solely at your own risk and judgment.
> 
> While the installer creates timestamped backups before applying changes, the author and contributors assume **no liability or responsibility** for any potential system damage, corrupted configurations, data loss, or other issues resulting from the use or execution of this repository. Always inspect shell scripts before running them on your machine.

---

## 📜 License
Released under the [MIT License](LICENSE). Designed for the Omarchy community.

