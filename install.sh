#!/usr/bin/env bash
set -e

# ==============================================================================
#  Midnight-Doll // Cyberdeck HUD - Automated Installer
# ==============================================================================

BOLD="\033[1m"
PINK="\033[38;2;255;81;197m"
VIOLET="\033[38;2;187;154;247m"
CYAN="\033[36m"
GREEN="\033[32m"
YELLOW="\033[33m"
RESET="\033[0m"

echo -e "${PINK}${BOLD}"
cat << "BANNER"
  __  __ _     _       _       _     _         ____        _ _ 
 |  \/  (_) __| |_ __ (_) __ _| |__ | |_      |  _ \  ___ | | |
 | |\/| | |/ _` | '_ \| |/ _` | '_ \| __|_____| | | |/ _ \| | |
 | |  | | | (_| | | | | | (_| | | | | |_|_____| |_| | (_) | | |
 |_|  |_|_|\__,_|_| |_|_|\__, |_| |_|\__|     |____/ \___/|_|_|
                         |___/      // CYBERDECK HUD
BANNER
echo -e "${RESET}"

DOTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="${HOME}/.config/omarchy/backups/midnight-doll-$(date +%Y%m%d_%H%M%S)"

echo -e "${VIOLET}[*] Checking environment & active configuration...${RESET}"

# Detect current active theme
ACTIVE_THEME=""
if [ -f "${HOME}/.local/state/omarchy/current/theme.name" ]; then
  ACTIVE_THEME="$(cat "${HOME}/.local/state/omarchy/current/theme.name" | tr -d '[:space:]')"
fi
if [ -z "${ACTIVE_THEME}" ]; then
  ACTIVE_THEME="default"
fi
echo -e "${CYAN}[i] Detected current active theme:${RESET} ${BOLD}${ACTIVE_THEME}${RESET}"

# ==============================================================================
#  Interactive Setup Prompts
# ==============================================================================

prompt_confirm() {
  local prompt="$1"
  local default_yes="${2:-true}"
  if command -v gum &> /dev/null && [ -t 0 ]; then
    if [ "$default_yes" = true ]; then
      gum confirm --default=true "$prompt"
    else
      gum confirm --default=false "$prompt"
    fi
  else
    local yn="[Y/n]"
    [ "$default_yes" = false ] && yn="[y/N]"
    local ans=""
    if [ -t 0 ]; then
      read -rp "$prompt $yn: " ans
    fi
    if [ "$default_yes" = true ]; then
      case "$ans" in
        [nN][oO]|[nN]) return 1 ;;
        *) return 0 ;;
      esac
    else
      case "$ans" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
      esac
    fi
  fi
}

prompt_choose() {
  local header="$1"
  shift
  local options=("$@")
  if command -v gum &> /dev/null && [ -t 0 ]; then
    gum choose --header="$header" "${options[@]}"
  elif [ -t 0 ]; then
    echo -e "\n$header" >&2
    local PS3="Select an option (1-${#options[@]}): "
    select opt in "${options[@]}"; do
      if [ -n "$opt" ]; then
        echo "$opt"
        break
      fi
    done
  else
    echo "${options[0]}"
  fi
}

prompt_input() {
  local header="$1"
  local default_val="$2"
  local placeholder="${3:-}"
  if command -v gum &> /dev/null && [ -t 0 ]; then
    local res
    res=$(gum input --value="$default_val" --placeholder="$placeholder" --header="$header")
    echo "${res:-$default_val}"
  elif [ -t 0 ]; then
    local res
    read -rp "$header [$default_val]: " res
    echo "${res:-$default_val}"
  else
    echo "$default_val"
  fi
}

echo -e "\n${VIOLET}[*] Interactive Configuration Setup${RESET}"

# ------------------------------------------------------------------------------
# Step 1: CAVA Audio Visualizer Check & Optional Install
# (Only prompted if cava is not already installed on the system)
# ------------------------------------------------------------------------------
if command -v cava &> /dev/null; then
  echo -e "    ${GREEN}✓ 'cava' audio visualizer detected at $(command -v cava)${RESET}"
else
  echo -e "\n${PINK}[Step 1/4] Audio Visualizer Setup${RESET}"
  if prompt_confirm "This theme incorporates a cava visualizer. Would you like to install cava?" true; then
    echo -e "${VIOLET}[*] Installing cava...${RESET}"
    if command -v omarchy &> /dev/null; then
      omarchy pkg add cava || sudo pacman -S --needed --noconfirm cava || true
    elif command -v pacman &> /dev/null; then
      sudo pacman -S --needed --noconfirm cava || true
    elif command -v yay &> /dev/null; then
      yay -S --needed --noconfirm cava || true
    elif command -v paru &> /dev/null; then
      paru -S --needed --noconfirm cava || true
    fi
    if command -v cava &> /dev/null; then
      echo -e "    ${GREEN}✓ 'cava' installed successfully!${RESET}"
    else
      echo -e "    ${YELLOW}[!] Could not automatically install cava. You can install it manually later with 'sudo pacman -S cava'.${RESET}"
    fi
  else
    echo -e "    ${YELLOW}[!] Skipping cava installation.${RESET}"
  fi
fi

# ------------------------------------------------------------------------------
# Step 2: Theme Accent Color Configuration
# ------------------------------------------------------------------------------
echo -e "\n${PINK}[Step 2/4] Accent Color Configuration${RESET}"
echo -e "${VIOLET}The default accent color for this theme is Cyberpunk Magenta (#ff51c5).${RESET}"
COLOR_CHOICE=$(prompt_choose "Choose an accent color for the theme:" \
  "Cyberpunk Magenta [#ff51c5] (Default)" \
  "Neon Green [#00ff9f]" \
  "Cyber Red [#ff3366]" \
  "Electric Cyan [#00f0ff]" \
  "Vibrant Violet [#bb9af7]" \
  "Acid Yellow [#ffe600]" \
  "Hot Orange [#ff8800]" \
  "Custom Hex Code")

CHOSEN_HEX="#ff51c5"
case "$COLOR_CHOICE" in
  *"#ff51c5"*) CHOSEN_HEX="#ff51c5" ;;
  *"#00ff9f"*) CHOSEN_HEX="#00ff9f" ;;
  *"#ff3366"*) CHOSEN_HEX="#ff3366" ;;
  *"#00f0ff"*) CHOSEN_HEX="#00f0ff" ;;
  *"#bb9af7"*) CHOSEN_HEX="#bb9af7" ;;
  *"#ffe600"*) CHOSEN_HEX="#ffe600" ;;
  *"#ff8800"*) CHOSEN_HEX="#ff8800" ;;
  "Custom Hex Code")
    while true; do
      CUSTOM_INPUT=$(prompt_input "Enter a custom hex color (e.g. #ff007f or 00e5ff):" "#ff51c5" "#RRGGBB")
      CUSTOM_INPUT="$(echo "$CUSTOM_INPUT" | tr -d '[:space:]')"
      [[ "$CUSTOM_INPUT" != \#* ]] && CUSTOM_INPUT="#$CUSTOM_INPUT"
      if [[ "$CUSTOM_INPUT" =~ ^#[0-9a-fA-F]{6}$ ]]; then
        CHOSEN_HEX="$CUSTOM_INPUT"
        break
      else
        echo -e "${YELLOW}[!] Invalid hex code '$CUSTOM_INPUT'. Format must be 6 hex characters (e.g. #ff007f). Please try again.${RESET}"
      fi
    done
    ;;
  *) CHOSEN_HEX="#ff51c5" ;;
esac
echo -e "    ${GREEN}✓ Accent color set to:${RESET} ${BOLD}${CHOSEN_HEX}${RESET}"

# ------------------------------------------------------------------------------
# Step 3: Top Bar HUD Text Configuration
# ------------------------------------------------------------------------------
echo -e "\n${PINK}[Step 3/4] Top Bar HUD Header Text${RESET}"
echo -e "${VIOLET}Default header text is: MIDNIGHT-DOLL // HUD${RESET}"
HUD_TEXT=$(prompt_input "Change the HUD text (or press Enter to keep default):" "MIDNIGHT-DOLL // HUD" "MIDNIGHT-DOLL // HUD")
if [[ "$HUD_TEXT" == *" // "* ]]; then
  HUD_TITLE="${HUD_TEXT%% // *}"
  HUD_SUBTITLE="${HUD_TEXT#* // }"
elif [[ "$HUD_TEXT" == *"/"* ]]; then
  HUD_TITLE="$(echo "$HUD_TEXT" | awk -F'/' '{print $1}' | sed 's/[[:space:]]*$//')"
  HUD_SUBTITLE="$(echo "$HUD_TEXT" | awk -F'/' '{print $2}' | sed 's/^[[:space:]]*//')"
else
  HUD_TITLE="$HUD_TEXT"
  HUD_SUBTITLE=""
fi
echo -e "    ${GREEN}✓ HUD title set to:${RESET} ${BOLD}${HUD_TITLE}${HUD_SUBTITLE:+ // $HUD_SUBTITLE}${RESET}"

# ------------------------------------------------------------------------------
# Step 4: Omarchy Menu Launcher Icon Configuration
# ------------------------------------------------------------------------------
echo -e "\n${PINK}[Step 4/4] Omarchy Menu Launcher Icon${RESET}"
echo -e "${CYAN}Browse Nerd Font glyphs at:${RESET} ${BOLD}https://www.nerdfonts.com/cheat-sheet${RESET}"
echo -e "${VIOLET}Current default is the Cyberdeck Skull glyph: 󰚌${RESET}"
MENU_GLYPH=$(prompt_input "Enter a menu icon glyph for omarchy.menu (or press Enter for default 󰚌):" "󰚌" "󰚌")
echo -e "    ${GREEN}✓ Menu icon set to:${RESET} ${BOLD}${MENU_GLYPH}${RESET}"

# Create comprehensive backup directory
mkdir -p "${BACKUP_DIR}"
echo -e "${VIOLET}[*] Creating comprehensive backup at:${RESET} ${BACKUP_DIR}"

# 1. Record original theme metadata
echo "${ACTIVE_THEME}" > "${BACKUP_DIR}/original_theme.txt"

# 2. Backup currently active theme files
if [ -n "${ACTIVE_THEME}" ] && [ -d "${HOME}/.config/omarchy/themes/${ACTIVE_THEME}" ]; then
  mkdir -p "${BACKUP_DIR}/active-theme"
  cp -r "${HOME}/.config/omarchy/themes/${ACTIVE_THEME}" "${BACKUP_DIR}/active-theme/"
  echo -e "    ✓ Backed up active theme directory: ${ACTIVE_THEME}"
fi

# 3. Backup existing Midnight-Doll theme if present
if [ -d "${HOME}/.config/omarchy/themes/midnight-doll" ]; then
  mkdir -p "${BACKUP_DIR}/existing-midnight-doll"
  cp -r "${HOME}/.config/omarchy/themes/midnight-doll" "${BACKUP_DIR}/existing-midnight-doll/"
  echo -e "    ✓ Backed up existing Midnight-Doll configuration"
fi

# 4. Backup existing omarchy configs
for cfg in "shell.json" "sys-hud.sh" "cava.conf" "midnight-shortcuts.json"; do
  if [ -f "${HOME}/.config/omarchy/${cfg}" ]; then
    cp "${HOME}/.config/omarchy/${cfg}" "${BACKUP_DIR}/"
    echo -e "    ✓ Backed up config: ~/.config/omarchy/${cfg}"
  fi
done

# 5. Backup existing Midnight-Doll user plugins if present
if compgen -G "${HOME}/.config/omarchy/plugins/midnight-doll.*" > /dev/null; then
  mkdir -p "${BACKUP_DIR}/existing-plugins"
  cp -r "${HOME}/.config/omarchy/plugins/midnight-doll."* "${BACKUP_DIR}/existing-plugins/" 2>/dev/null || true
  echo -e "    ✓ Backed up existing Midnight-Doll user plugins"
fi

# 6. Generate detailed backup manifest
cat << MANIFEST > "${BACKUP_DIR}/backup_manifest.json"
{
  "timestamp": "$(date -Iseconds 2>/dev/null || date)",
  "original_theme": "${ACTIVE_THEME}",
  "user": "${USER}",
  "backup_dir": "${BACKUP_DIR}",
  "chosen_accent_color": "${CHOSEN_HEX}",
  "hud_text": "${HUD_TEXT}",
  "menu_icon": "${MENU_GLYPH}"
}
MANIFEST

echo -e "\n${VIOLET}[*] Deploying Theme & Scripts to ~/.config/omarchy/...${RESET}"
mkdir -p "${HOME}/.config/omarchy/themes/midnight-doll"
cp -r "${DOTS_DIR}/config/omarchy/themes/midnight-doll/"* "${HOME}/.config/omarchy/themes/midnight-doll/"
cp "${DOTS_DIR}/config/omarchy/sys-hud.sh" "${HOME}/.config/omarchy/"
cp "${DOTS_DIR}/config/omarchy/cava.conf" "${HOME}/.config/omarchy/"
if [ ! -f "${HOME}/.config/omarchy/midnight-shortcuts.json" ]; then
  cp "${DOTS_DIR}/config/omarchy/midnight-shortcuts.json" "${HOME}/.config/omarchy/"
fi
chmod +x "${HOME}/.config/omarchy/sys-hud.sh"

# Apply customized accent color if changed
if [ "${CHOSEN_HEX}" != "#ff51c5" ]; then
  echo -e "    ✓ Applying custom accent color ${CHOSEN_HEX} to theme configs..."
  python3 -c "
import sys, re
target_colors, target_ghostty, target_hypr, hex_col = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
with open(target_colors, 'r', encoding='utf-8') as f:
    c = f.read()
c = re.sub(r'accent = \"#[0-9a-fA-F]{6}\"', f'accent = \"{hex_col}\"', c)
c = re.sub(r'foreground = \"#[0-9a-fA-F]{6}\"', f'foreground = \"{hex_col}\"', c)
with open(target_colors, 'w', encoding='utf-8') as f:
    f.write(c)

with open(target_ghostty, 'r', encoding='utf-8') as f:
    g = f.read()
g = re.sub(r'foreground = #[0-9a-fA-F]{6}', f'foreground = {hex_col}', g)
with open(target_ghostty, 'w', encoding='utf-8') as f:
    f.write(g)

hex_raw = hex_col.lstrip('#')
with open(target_hypr, 'r', encoding='utf-8') as f:
    h = f.read()
h = re.sub(r'active_border_color = \"rgb\([0-9a-fA-F]{6}\)\"', f'active_border_color = \"rgb({hex_raw})\"', h)
with open(target_hypr, 'w', encoding='utf-8') as f:
    f.write(h)
" "${HOME}/.config/omarchy/themes/midnight-doll/colors.toml" \
  "${HOME}/.config/omarchy/themes/midnight-doll/ghostty.conf" \
  "${HOME}/.config/omarchy/themes/midnight-doll/hyprland.lua" \
  "${CHOSEN_HEX}"
fi

# Deploy user plugins to ~/.config/omarchy/plugins/
echo -e "${VIOLET}[*] Deploying Midnight-Doll Cyberdeck plugins to ~/.config/omarchy/plugins/...${RESET}"
PLUGINS_DIR="${HOME}/.config/omarchy/plugins"
OMARCHY_SYS_PLUGINS="${OMARCHY_PATH:-/usr/share/omarchy}/shell/plugins"

# 1. Bar plugin (Dual-bar HUD, CAVA visualizer, live telemetry)
mkdir -p "${PLUGINS_DIR}/midnight-doll.bar/widgets"
if [ -d "${OMARCHY_SYS_PLUGINS}/bar" ]; then
  cp -r "${OMARCHY_SYS_PLUGINS}/bar/"* "${PLUGINS_DIR}/midnight-doll.bar/" 2>/dev/null || true
fi
cp "${DOTS_DIR}/shell-patch/plugins/bar/Bar.qml" "${PLUGINS_DIR}/midnight-doll.bar/"
cp "${DOTS_DIR}/shell-patch/plugins/bar/widgets/Workspaces.qml" "${PLUGINS_DIR}/midnight-doll.bar/widgets/"
python3 -c "
import sys, re
target_bar, title, subtitle, glyph = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
with open(target_bar, 'r', encoding='utf-8') as f:
    c = f.read()
c = re.sub(r'property string hudTitle: \".*?\"', f'property string hudTitle: \"{title}\"', c)
c = re.sub(r'property string hudSubtitle: \".*?\"', f'property string hudSubtitle: \"{subtitle}\"', c)
c = re.sub(r'property string menuIcon: \".*?\"', f'property string menuIcon: \"{glyph}\"', c)
with open(target_bar, 'w', encoding='utf-8') as f:
    f.write(c)
" "${PLUGINS_DIR}/midnight-doll.bar/Bar.qml" "${HUD_TITLE}" "${HUD_SUBTITLE}" "${MENU_GLYPH}"
cat << 'EOF' > "${PLUGINS_DIR}/midnight-doll.bar/manifest.json"
{
  "schemaVersion": 1,
  "id": "midnight-doll.bar",
  "name": "Midnight Doll Cyberdeck Bar",
  "version": "1.0.0",
  "author": "Midnight Doll",
  "description": "Dual-bar HUD & visualizer",
  "kinds": [
    "bar"
  ],
  "entryPoints": {
    "bar": "Bar.qml"
  }
}
EOF

# 2. Workspaces widget (bracketed workspaces)
mkdir -p "${PLUGINS_DIR}/midnight-doll.workspaces"
cp "${DOTS_DIR}/shell-patch/plugins/bar/widgets/Workspaces.qml" "${PLUGINS_DIR}/midnight-doll.workspaces/"
cat << 'EOF' > "${PLUGINS_DIR}/midnight-doll.workspaces/manifest.json"
{
  "schemaVersion": 1,
  "id": "midnight-doll.workspaces",
  "name": "Midnight Doll Workspaces",
  "version": "1.0.0",
  "author": "Midnight Doll",
  "description": "Retro bracketed workspace switcher",
  "kinds": [
    "bar-widget"
  ],
  "entryPoints": {
    "barWidget": "Workspaces.qml"
  },
  "barWidget": {
    "displayName": "Midnight Doll Workspaces",
    "description": "Retro bracketed workspace switcher",
    "category": "Compositor",
    "allowMultiple": false
  },
  "omarchy": {
    "clonedFrom": "omarchy.workspaces"
  }
}
EOF

# Remove legacy midnight-doll.menu if present
rm -rf "${PLUGINS_DIR}/midnight-doll.menu"

# 3. Clock widget (military uppercase format)
mkdir -p "${PLUGINS_DIR}/midnight-doll.clock"
if [ -d "${OMARCHY_SYS_PLUGINS}/panels/clock" ]; then
  cp -r "${OMARCHY_SYS_PLUGINS}/panels/clock/"* "${PLUGINS_DIR}/midnight-doll.clock/" 2>/dev/null || true
fi
cp "${DOTS_DIR}/shell-patch/plugins/panels/clock/BarWidget.qml" "${PLUGINS_DIR}/midnight-doll.clock/"
cat << 'EOF' > "${PLUGINS_DIR}/midnight-doll.clock/manifest.json"
{
  "schemaVersion": 1,
  "id": "midnight-doll.clock",
  "name": "Midnight Doll Clock",
  "version": "1.0.0",
  "author": "Midnight Doll",
  "description": "Military Monospace Header Clock",
  "kinds": [
    "bar-widget"
  ],
  "entryPoints": {
    "barWidget": "BarWidget.qml"
  },
  "barWidget": {
    "displayName": "Midnight Doll Clock",
    "description": "Military Monospace Header Clock",
    "category": "Time",
    "allowMultiple": false
  },
  "omarchy": {
    "clonedFrom": "omarchy.clock"
  }
}
EOF

# Activate theme and plugins if omarchy CLI is available
if command -v omarchy &> /dev/null; then
  echo -e "${PINK}[*] Activating Midnight-Doll theme & cyberdeck bar...${RESET}"
  omarchy theme set "Midnight Doll" || true
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  omarchy bar use midnight-doll.bar || true
  omarchy plugin enable midnight-doll.workspaces || true
  omarchy plugin enable midnight-doll.clock || true
  omarchy plugin enable omarchy.menu || true
  omarchy restart shell || true
fi

echo -e "\n${GREEN}${BOLD}✓ Midnight-Doll // Cyberdeck HUD successfully installed!${RESET}"
echo -e "    ${PINK}• Accent Color:${RESET} ${CHOSEN_HEX}"
echo -e "    ${PINK}• HUD Header:${RESET}   ${HUD_TITLE}${HUD_SUBTITLE:+ // $HUD_SUBTITLE}"
echo -e "    ${PINK}• Menu Icon:${RESET}    ${MENU_GLYPH}"
echo -e "\n${PINK}Press Win+Space or inspect your top & left bars to explore.${RESET}"
echo -e "${VIOLET}To restore your previous setup at any time, run: ./uninstall.sh${RESET}\n"
