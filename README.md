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

*Ultra-dense, claustrophobic, retro-futuristic hacker cyberdeck interface featuring custom audio visualizers, live telemetry, dual-bar sequencing, attached shelf drawers, and solid pitch-black aesthetics.*

</div>

---

## 📸 Screenshots

<p align="center">
  <img src="Example Screenshots/image1.png" alt="Midnight Doll Desktop Overview" width="49%">
  <img src="Example Screenshots/image2.png" alt="Midnight Doll Shell In Action" width="49%">
</p>
<p align="center">
  <img src="Example Screenshots/image3.png" alt="Midnight Doll Workspace & Terminal" width="49%">
  <img src="Example Screenshots/image4.png" alt="Midnight Doll Attached Shelves & Drawers" width="49%">
</p>
<p align="center">
  <img src="Example Screenshots/image5.png" alt="Midnight Doll Minimal Setup" width="99%">
</p>

---

## ⚡ Key Features

- 💀 **Cyberdeck Skull Menu Launcher**: Dedicated **18px Neon Pink Nerd Font Skull (`󰚌`)** menu icon on the top bar with full native integration with the official Omarchy application launcher and shell menus.
- 🎛️ **Dual-Bar Sequencing Architecture**:
  - **Top Bar (30px)**: Full-width priority header with solid pitch-black `#010101` backplane and neon accent underline.
  - **Left Launcher Panel (36px)**: Edge-flush vertical app launcher with interactive right-click JSON shortcut editor.
  - **Pixel-Perfect Adaptive Curved Seam**: GPU vector `QtQuick.Shapes` curve integrated natively into the panel surface without standalone overlay windows, scaling flawlessly across fractional monitor scales and adapting its stroke dynamically to active/inactive top-left window borders.
- 📑 **Attached Cyberdeck Shelf Drawers & Popouts**:
  - All widget popups and drawer menus (Notification Center, Calendar, System HUD, Power, Audio, Network, AI Usage, etc.) project outwards as **seamless attached shelves** rather than detached floating popups.
  - Continuous vector pink accent borders wrap around the panel with **0px divider** against the chassis.
  - **Multi-Edge Perimeter Snapping**: Top-bar drawers (such as Notification Center) automatically snap flush to the left bar seam ($x = 35$), while left-bar drawers snap flush to the bottom screen edge.
  - **Adaptive Floating Mode**: Double-clicking to toggle transparent bar mode seamlessly converts shelves into standalone `#010101` floating cards with 4-corner rounded borders to preserve readability against arbitrary wallpapers or open windows.
- 🎬 **Fluid Bar Summon & Dismiss Animations (`Super+Shift+Space`)**:
  - Smooth cubic sliding and opacity animations when toggling bars on/off via `Super+Shift+Space`.
  - Top bar slides vertically off-screen, left bar slides horizontally off-screen.
  - Immediate pointer input release: the input mask drops to zero immediately upon dismiss so games and full-screen windows are never blocked while animating.
- 🖥️ **Intelligent Fullscreen Sync (`omarchy-fullscreen-bar-sync`)**:
  - Automatically hides bars when launching fullscreen games, media, or applications.
  - Preserves user preferences: remembers whether bars were explicitly hidden on the desktop, ensuring they only restore if they were auto-hidden by fullscreen.
- 📊 **Real-Time Ultra-Fast System Telemetry & Interactive HUD**:
  - Custom 3ms metrics sampler monitoring **CPU Temp & %**, **Fan Speed**, **RAM (Used / Total)**, **Disk %**, **Live Network TX / RX** rates, and **Active Socket Connections**.
  - Interactive click action: click the accent header/subtitle to instantly summon a floating **btop** activity monitor or your own custom command.
  - Supports dual-tone (`TITLE // SUBTITLE`) or single-word accent branding (e.g. `ro0tUser`).
- 🎵 **Violet LED Dot-Matrix Audio Visualizer**:
  - Pipewire-driven **CAVA spectrum capture**.
  - **22-column × 5-tier discrete violet LED dot-matrix** (`#bb9af7`) with **neon pink peak indicators** (`#ff51c5`).
  - **Inverted Stacked Audio Gauges**: Pinched `AIR` (top), `MID` (middle), and `BASS` (bottom) level meters.
- 🕒 **Interactive Military Monospace Header Clock**:
  - Centered monospace date & time display with independent, clickable sections.
  - Click to cycle display formats: 12-hour, 24-hour colonless, and precision seconds toggle.
- 📟 **Integrated Notification Center (`midnight-doll.notifications`)**:
  - Cyberdeck notification drawer with multi-edge shelf geometry, action controls, and an alert badge featuring native two-tier heuristics.
- 🔒 **Total Theme Isolation**:
  - Zero style leak. Switching to standard Omarchy themes (e.g. *Kanagawa*, *Catppuccin*) instantly unloads the left bar, HUD, visualizer, and QML overrides, reverting 100% cleanly to stock settings.

---

## 🎮 Controls & Interactions

| Shortcut / Gesture | Target | Action |
| :--- | :--- | :--- |
| `Super + Shift + Space` | Entire Suite | Smoothly summon or dismiss top and left bars with slide transitions |
| `Double-Click` | Bar Background | Toggle solid pitch-black (`#010101`) vs transparent bar backplane |
| `Right-Click` | Left Launcher Panel | Open graphical launcher shortcut manager (add, reorder, delete items) |
| `Click` | HUD Title / Subtitle | Launch configured activity monitor (Default: floating `btop`) |
| `Click` | Header Date / Time | Cycle time format (12-hour / 24-hour / toggle precision seconds) |
| `Click` | Bar Widgets & Icons | Open attached cyberpunk shelf drawers with continuous borders |

---

## 📦 File Tree Structure

```text
midnight-doll-dots/
├── README.md                      # Documentation, showcase & architecture
├── Example Screenshots/           # Visual desktop showcase previews
│   ├── image1.png
│   ├── image2.png
│   ├── image3.png
│   ├── image4.png
│   └── image5.png
├── install.sh                     # Automated 1-click installer & backup generator
├── uninstall.sh                   # Instant rollback script
├── bin/
│   └── omarchy-fullscreen-bar-sync# Fullscreen bar state & auto-hide sync engine
├── config/
│   └── omarchy/
│       ├── sys-hud.sh             # Fast real-time system metrics engine
│       ├── cava.conf              # Audio spectrum capture profile
│       ├── midnight-shortcuts.json# Left bar launcher shortcuts store
│       └── themes/
│           └── midnight-doll/     # Colors, Hyprland rules, and terminal profiles
│               ├── colors.toml    # Theme color definitions
│               ├── hyprland.lua   # Border, gaps, and window decorations
│               ├── ghostty.conf   # Ghostty terminal palette configuration
│               └── backgrounds/   # Curated Midnight Doll retro-cyberpunk wallpapers
└── shell-patch/
    ├── qml/                       # QML shell overrides for attached shelf drawers
    │   └── qs/
    │       └── Ui/
    │           ├── KeyboardPanel.qml # Attached shelf drawers with edge snapping
    │           ├── PopupCard.qml     # Attached popup cards & transparent adaptation
    │           └── qmldir            # QML module registry
    └── plugins/
        ├── bar/
        │   ├── Bar.qml            # Dual-bar HUD core engine, transitions & slot routing
        │   └── BarModel.js        # Multi-surface drag-and-drop model extension
        ├── notifications/         # Cyberdeck Notification Center plugin
        │   ├── manifest.json      # Notification plugin manifest
        │   ├── Panel.qml          # Attached notification drawer & action controls
        │   └── helper.py          # Notification daemon & history helper
        ├── sys-hud/
        │   ├── manifest.json      # Modular System HUD manifest
        │   └── SystemHud.qml      # Modular CPU, Temp, Fan, RAM, Disk, Net metrics widget
        └── visualizer/
            ├── manifest.json      # Modular Audio Visualizer manifest
            └── Visualizer.qml     # Modular CAVA LED dot-matrix widget
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
2. Deploy the theme, wallpapers, scripts, and modular user plugins.
3. Deploy QML shell overrides to `~/.config/omarchy/qml/` and set `QML_IMPORT_PATH`.
4. Clean up any obsolete shortcuts or stock wallpapers.
5. Activate **Midnight-Doll** and reload your shell live.

---

## 🛠️ Customization

### Left Bar App Shortcuts
Edit `~/.config/omarchy/midnight-shortcuts.json` or simply **Right-Click** anywhere on the Left Bar to open the graphical in-bar shortcut editor!

```json
[
  { "glyph": "󰞷", "command": "omarchy-launch-terminal" },
  { "glyph": "󰇧", "command": "omarchy-launch-browser" },
  { "glyph": "󰉋", "command": "omarchy-launch-nautilus" },
  { "glyph": "", "command": "omarchy-launch-editor" },
  { "glyph": "", "command": "omarchy-launch-webapp \"https://chess.com/\"" }
]
```

### Color Palette & Live Accent Switcher
Dual-tone colors can be configured during installation, passed via CLI flags (`./install.sh --accent #39ff14`), or changed dynamically anytime using the included **`set-accent.sh`** tool:

```bash
# Switch accent colors live anytime without reinstalling
~/.config/omarchy/set-accent.sh #39ff14               # Computes harmonic complement automatically
~/.config/omarchy/set-accent.sh #00ff9f #00f0ff       # Custom Primary and Complimentary pairing
~/.config/omarchy/set-accent.sh cyan purple           # Accepts color names and 3/6-digit hex
```

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

The uninstaller restores your original `shell.json`, removes deployed plugins and QML overrides, cleans up environment configurations, and safely resets your bar.

---

## ⚠️ Disclaimer

> [!WARNING]
> This project, scripts, and configuration files are provided **"AS IS"** without warranty of any kind, express or implied. Execute and install this software solely at your own risk and judgment.
> 
> While the installer creates timestamped backups before applying changes, the author and contributors assume **no liability or responsibility** for any potential system damage, corrupted configurations, data loss, or other issues resulting from the use or execution of this repository. Always inspect shell scripts before running them on your machine.

---

## 📜 License
Released under the [MIT License](LICENSE). Designed for the Omarchy community.
