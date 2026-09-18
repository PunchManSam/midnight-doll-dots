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

# CLI Argument Parsing for unattended / direct custom color setup
CLI_PRIMARY=""
CLI_SECONDARY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --accent|--primary|-a|-p)
      CLI_PRIMARY="$2"
      shift 2
      ;;
    --secondary|--complimentary|-s|-c)
      CLI_SECONDARY="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

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
  local default_val="${2:-}"
  local placeholder="${3:-}"
  if command -v gum &> /dev/null && [ -t 0 ]; then
    local res
    if [ -n "$default_val" ]; then
      res=$(gum input --value="$default_val" --placeholder="$placeholder" --header="$header")
    else
      res=$(gum input --placeholder="$placeholder" --header="$header")
    fi
    echo "${res:-$default_val}"
  elif [ -t 0 ]; then
    local res
    if [ -n "$default_val" ]; then
      read -rp "$header [$default_val]: " res
    else
      read -rp "$header: " res
    fi
    echo "${res:-$default_val}"
  else
    echo "$default_val"
  fi
}

normalize_color() {
  local input="$1"
  local fallback="${2:-}"
  input="$(echo "$input" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
  case "$input" in
    "magenta"|"pink") echo "#ff51c5"; return ;;
    "green"|"neon"|"lime"|"neon-green") echo "#00ff9f"; return ;;
    "red") echo "#ff3366"; return ;;
    "cyan"|"aqua"|"teal") echo "#00f0ff"; return ;;
    "violet"|"purple"|"lavender") echo "#bb9af7"; return ;;
    "yellow") echo "#ffe600"; return ;;
    "orange") echo "#ff8800"; return ;;
    "blue"|"sky") echo "#7da6ff"; return ;;
    "white") echo "#ffffff"; return ;;
  esac
  [[ "$input" != \#* ]] && input="#$input"
  if [[ "$input" =~ ^#[0-9a-f]{3}$ ]]; then
    local r="${input:1:1}" g="${input:2:1}" b="${input:3:1}"
    echo "#${r}${r}${g}${g}${b}${b}"
    return
  fi
  if [[ "$input" =~ ^#[0-9a-f]{6}$ ]]; then
    echo "$input"
    return
  fi
  echo "$fallback"
}

calc_complement() {
  local hex="$1"
  python3 -c "
import colorsys, sys
try:
    h_str = sys.argv[1].lstrip('#')
    r, g, b = int(h_str[0:2], 16)/255.0, int(h_str[2:4], 16)/255.0, int(h_str[4:6], 16)/255.0
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    ch = (h + 0.5) % 1.0
    cr, cg, cb = colorsys.hsv_to_rgb(ch, s, v)
    print(f'#{int(round(cr*255)):02x}{int(round(cg*255)):02x}{int(round(cb*255)):02x}')
except Exception:
    print('#bb9af7')
" "$hex"
}

echo -e "\n${VIOLET}[*] Interactive Configuration Setup${RESET}"

# ------------------------------------------------------------------------------
# Step 1: CAVA Audio Visualizer Check & Optional Install
# (Only prompted if cava is not already installed on the system)
# ------------------------------------------------------------------------------
if command -v cava &> /dev/null; then
  echo -e "    ${GREEN}✓ 'cava' audio visualizer detected at $(command -v cava)${RESET}"
else
  echo -e "\n${PINK}[Step 1/5] Audio Visualizer Setup${RESET}"
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
# Step 2: Theme Accent Color Configuration (Dual-Tone Palette)
# ------------------------------------------------------------------------------
echo -e "\n${PINK}[Step 2/5] Dual-Tone Accent Color Configuration${RESET}"

if [ -n "$CLI_PRIMARY" ]; then
  CHOSEN_PRIMARY="$(normalize_color "$CLI_PRIMARY" "#ff51c5")"
  echo -e "    ${GREEN}✓ Primary Accent set from CLI flag to:${RESET} ${BOLD}${CHOSEN_PRIMARY}${RESET}"
else
  echo -e "${VIOLET}Select the Primary Accent color (active workspaces, buttons, peak LEDs, window borders):${RESET}"
  COLOR_CHOICE=$(prompt_choose "Choose Primary Accent color:" \
    "Cyberpunk Magenta [#ff51c5] (Default)" \
    "Enter Custom Color / Hex Code..." \
    "Neon Green [#00ff9f]" \
    "Cyber Red [#ff3366]" \
    "Electric Cyan [#00f0ff]" \
    "Vibrant Violet [#bb9af7]" \
    "Acid Yellow [#ffe600]" \
    "Hot Orange [#ff8800]")

  CHOSEN_PRIMARY="#ff51c5"
  case "$COLOR_CHOICE" in
    *"#ff51c5"*) CHOSEN_PRIMARY="#ff51c5" ;;
    *"#00ff9f"*) CHOSEN_PRIMARY="#00ff9f" ;;
    *"#ff3366"*) CHOSEN_PRIMARY="#ff3366" ;;
    *"#00f0ff"*) CHOSEN_PRIMARY="#00f0ff" ;;
    *"#bb9af7"*) CHOSEN_PRIMARY="#bb9af7" ;;
    *"#ffe600"*) CHOSEN_PRIMARY="#ffe600" ;;
    *"#ff8800"*) CHOSEN_PRIMARY="#ff8800" ;;
    *"Custom"*)
      while true; do
        CUSTOM_INPUT=$(prompt_input "Enter custom primary color (hex e.g. #ff007f or ff007f, #f0f, or name e.g. cyan):" "" "#RRGGBB")
        CUSTOM_INPUT="$(echo "$CUSTOM_INPUT" | tr -d '[:space:]')"
        if [ -z "$CUSTOM_INPUT" ]; then
          CHOSEN_PRIMARY="#ff51c5"
          break
        fi
        NORMALIZED="$(normalize_color "$CUSTOM_INPUT" "")"
        if [ -n "$NORMALIZED" ]; then
          CHOSEN_PRIMARY="$NORMALIZED"
          break
        else
          echo -e "${YELLOW}[!] Invalid color '$CUSTOM_INPUT'. Enter a hex code (e.g. #ff007f or ff007f), 3-digit hex (#f0f), or color name. Please try again.${RESET}"
        fi
      done
      ;;
    *) CHOSEN_PRIMARY="#ff51c5" ;;
  esac
  echo -e "    ${GREEN}✓ Primary Accent set to:${RESET} ${BOLD}${CHOSEN_PRIMARY}${RESET}"
fi
CHOSEN_HEX="${CHOSEN_PRIMARY}"

# Determine recommended complimentary color based on chosen primary
case "$CHOSEN_PRIMARY" in
  "#ff51c5") REC_HEX="#bb9af7"; REC_LABEL="Vibrant Violet [#bb9af7] (Default Cyberpunk Pairing)" ;;
  "#00ff9f") REC_HEX="#00f0ff"; REC_LABEL="Electric Cyan [#00f0ff]" ;;
  "#ff3366") REC_HEX="#00f0ff"; REC_LABEL="Electric Cyan [#00f0ff]" ;;
  "#00f0ff") REC_HEX="#ff51c5"; REC_LABEL="Cyberpunk Magenta [#ff51c5]" ;;
  "#bb9af7") REC_HEX="#00f0ff"; REC_LABEL="Electric Cyan [#00f0ff]" ;;
  "#ffe600") REC_HEX="#bb9af7"; REC_LABEL="Vibrant Violet [#bb9af7]" ;;
  "#ff8800") REC_HEX="#00f0ff"; REC_LABEL="Electric Cyan [#00f0ff]" ;;
  *)
    CALC_HEX="$(calc_complement "$CHOSEN_PRIMARY")"
    REC_HEX="$CALC_HEX"
    REC_LABEL="Harmonic Complement [${CALC_HEX}] (Calculated for ${CHOSEN_PRIMARY})"
    ;;
esac

if [ -n "$CLI_SECONDARY" ]; then
  CHOSEN_SECONDARY="$(normalize_color "$CLI_SECONDARY" "$REC_HEX")"
  echo -e "    ${GREEN}✓ Complimentary Accent set from CLI flag to:${RESET} ${BOLD}${CHOSEN_SECONDARY}${RESET}"
else
  echo -e "\n${VIOLET}Select the Complimentary / Secondary Accent color (HUD title, telemetry metrics, audio LED visualizer):${RESET}"
  COMP_CHOICE=$(prompt_choose "Choose Complimentary Accent color:" \
    "${REC_LABEL} (Recommended)" \
    "Enter Custom Color / Hex Code..." \
    "Vibrant Violet [#bb9af7]" \
    "Electric Cyan [#00f0ff]" \
    "Cyberpunk Magenta [#ff51c5]" \
    "Neon Green [#00ff9f]" \
    "Cyber Red [#ff3366]" \
    "Acid Yellow [#ffe600]" \
    "Hot Orange [#ff8800]" \
    "Ice Blue [#7da6ff]" \
    "Ghost White [#d0d0d0]")

  CHOSEN_SECONDARY="$REC_HEX"
  case "$COMP_CHOICE" in
    *"(Recommended)"*) CHOSEN_SECONDARY="$REC_HEX" ;;
    *"#bb9af7"*) CHOSEN_SECONDARY="#bb9af7" ;;
    *"#00f0ff"*) CHOSEN_SECONDARY="#00f0ff" ;;
    *"#ff51c5"*) CHOSEN_SECONDARY="#ff51c5" ;;
    *"#00ff9f"*) CHOSEN_SECONDARY="#00ff9f" ;;
    *"#ff3366"*) CHOSEN_SECONDARY="#ff3366" ;;
    *"#ffe600"*) CHOSEN_SECONDARY="#ffe600" ;;
    *"#ff8800"*) CHOSEN_SECONDARY="#ff8800" ;;
    *"#7da6ff"*) CHOSEN_SECONDARY="#7da6ff" ;;
    *"#d0d0d0"*) CHOSEN_SECONDARY="#d0d0d0" ;;
    *"Custom"*)
      while true; do
        CUSTOM_INPUT=$(prompt_input "Enter custom complimentary color (hex e.g. #00ffff, or name):" "" "#RRGGBB")
        CUSTOM_INPUT="$(echo "$CUSTOM_INPUT" | tr -d '[:space:]')"
        if [ -z "$CUSTOM_INPUT" ]; then
          CHOSEN_SECONDARY="$REC_HEX"
          break
        fi
        NORMALIZED="$(normalize_color "$CUSTOM_INPUT" "")"
        if [ -n "$NORMALIZED" ]; then
          CHOSEN_SECONDARY="$NORMALIZED"
          break
        else
          echo -e "${YELLOW}[!] Invalid color '$CUSTOM_INPUT'. Enter a hex code (e.g. #00ffff or 00ffff) or color name. Please try again.${RESET}"
        fi
      done
      ;;
    *) CHOSEN_SECONDARY="$REC_HEX" ;;
  esac
  echo -e "    ${GREEN}✓ Complimentary Accent set to:${RESET} ${BOLD}${CHOSEN_SECONDARY}${RESET}"
fi

# ------------------------------------------------------------------------------
# Step 3: Top Bar HUD Header Text
# ------------------------------------------------------------------------------
echo -e "\n${PINK}[Step 3/5] Top Bar HUD Header Text${RESET}"
echo -e "${VIOLET}Default header text is: MIDNIGHT-DOLL // HUD${RESET}"
echo -e "${CYAN}Tip: Use 'TITLE // SUBTITLE' (e.g. MIDNIGHT-DOLL // HUD) or a single title (e.g. ro0tUser).${RESET}"
echo -e "${CYAN}     A single title will be styled in your accent color and can launch a custom command on click.${RESET}"
HUD_TEXT=$(prompt_input "Enter HUD text (or press Enter to keep default):" "MIDNIGHT-DOLL // HUD" "MIDNIGHT-DOLL // HUD")
if [[ "$HUD_TEXT" == *" // "* ]]; then
  HUD_TITLE="${HUD_TEXT%% // *}"
  HUD_SUBTITLE="${HUD_TEXT#* // }"
elif [[ "$HUD_TEXT" == *"/"* ]]; then
  HUD_TITLE="$(echo "$HUD_TEXT" | awk -F'/' '{print $1}' | sed 's/[[:space:]]*$//')"
  HUD_SUBTITLE="$(echo "$HUD_TEXT" | awk -F'/' '{print $2}' | sed 's/^[[:space:]]*//')"
else
  HUD_TITLE=""
  HUD_SUBTITLE="$HUD_TEXT"
fi

if [ -n "$HUD_TITLE" ] && [ -n "$HUD_SUBTITLE" ]; then
  echo -e "    ${GREEN}✓ HUD title set to:${RESET} ${BOLD}${HUD_TITLE} // ${HUD_SUBTITLE}${RESET}"
elif [ -n "$HUD_SUBTITLE" ]; then
  echo -e "    ${GREEN}✓ HUD title set to:${RESET} ${BOLD}${HUD_SUBTITLE}${RESET} (accent subtitle)"
else
  echo -e "    ${GREEN}✓ HUD title set to:${RESET} ${BOLD}${HUD_TITLE}${RESET}"
fi

# ------------------------------------------------------------------------------
# Step 4: Top Bar HUD Click Command
# ------------------------------------------------------------------------------
CLICK_LABEL="${HUD_SUBTITLE:-$HUD_TITLE}"
echo -e "\n${PINK}[Step 4/5] Top Bar HUD Click Command${RESET}"
echo -e "${VIOLET}Clicking '${CLICK_LABEL}' on the top bar launches an application or terminal command.${RESET}"
echo -e "${VIOLET}Default is floating btop system monitor ('omarchy-launch-or-focus-tui btop').${RESET}"
HUD_CMD=$(prompt_input "Enter command to launch on click (or press Enter for default):" "omarchy-launch-or-focus-tui btop" "omarchy-launch-or-focus-tui btop")
if [ "$HUD_CMD" = "none" ] || [ "$HUD_CMD" = "off" ] || [ "$HUD_CMD" = "disabled" ]; then
  HUD_CMD=""
  echo -e "    ${YELLOW}[!] HUD click action disabled.${RESET}"
else
  echo -e "    ${GREEN}✓ HUD click command set to:${RESET} ${BOLD}${HUD_CMD}${RESET}"
fi

# ------------------------------------------------------------------------------
# Step 5: Omarchy Menu Launcher Icon Configuration
# ------------------------------------------------------------------------------
echo -e "\n${PINK}[Step 5/5] Omarchy Menu Launcher Icon${RESET}"
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
for cfg in "shell.json" "sys-hud.sh" "cava.conf" "midnight-shortcuts.json" "set-accent.sh"; do
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
  "primary_accent_color": "${CHOSEN_PRIMARY}",
  "secondary_accent_color": "${CHOSEN_SECONDARY}",
  "chosen_accent_color": "${CHOSEN_PRIMARY}",
  "hud_text": "${HUD_TEXT}",
  "hud_command": "${HUD_CMD}",
  "menu_icon": "${MENU_GLYPH}"
}
MANIFEST

echo -e "\n${VIOLET}[*] Deploying Theme & Scripts to ~/.config/omarchy/...${RESET}"
mkdir -p "${HOME}/.config/omarchy/themes/midnight-doll"
cp -r "${DOTS_DIR}/config/omarchy/themes/midnight-doll/"* "${HOME}/.config/omarchy/themes/midnight-doll/"
cp "${DOTS_DIR}/config/omarchy/sys-hud.sh" "${HOME}/.config/omarchy/"
cp "${DOTS_DIR}/config/omarchy/cava.conf" "${HOME}/.config/omarchy/"
cp "${DOTS_DIR}/config/omarchy/set-accent.sh" "${HOME}/.config/omarchy/"
if [ ! -f "${HOME}/.config/omarchy/midnight-shortcuts.json" ]; then
  cp "${DOTS_DIR}/config/omarchy/midnight-shortcuts.json" "${HOME}/.config/omarchy/"
fi
chmod +x "${HOME}/.config/omarchy/sys-hud.sh"
chmod +x "${HOME}/.config/omarchy/set-accent.sh"

# Apply customized accent & complimentary colors to theme configs
echo -e "    ✓ Applying dual-tone color scheme (${CHOSEN_PRIMARY} / ${CHOSEN_SECONDARY}) to theme configs..."
python3 - "${HOME}/.config/omarchy/themes/midnight-doll/colors.toml" \
  "${HOME}/.config/omarchy/themes/midnight-doll/ghostty.conf" \
  "${HOME}/.config/omarchy/themes/midnight-doll/hyprland.lua" \
  "${CHOSEN_PRIMARY}" \
  "${CHOSEN_SECONDARY}" << 'EOF'
import sys, re

colors_path, ghostty_path, hypr_path = sys.argv[1], sys.argv[2], sys.argv[3]
pri_hex, sec_hex = sys.argv[4].strip(), sys.argv[5].strip()

# Derive darker selection background from primary hex
try:
    pr, pg, pb = int(pri_hex[1:3], 16), int(pri_hex[3:5], 16), int(pri_hex[5:7], 16)
    sel_hex = f"#{int(pr * 0.5):02x}{int(pg * 0.5):02x}{int(pb * 0.5):02x}"
except Exception:
    sel_hex = "#7f2862"

# Derive inactive border glow from secondary hex
try:
    sr, sg, sb = int(sec_hex[1:3], 16), int(sec_hex[3:5], 16), int(sec_hex[5:7], 16)
    inactive_border = f"{int(sr * 0.22):02x}{int(sg * 0.22):02x}{int(sb * 0.22):02x}"
except Exception:
    inactive_border = "2b0938"

raw_pri = pri_hex.lstrip('#')

# 1. Update colors.toml
with open(colors_path, 'r', encoding='utf-8') as f:
    c = f.read()
c = re.sub(r'^accent = "#[0-9a-fA-F]{6}"', f'accent = "{pri_hex}"', c, flags=re.MULTILINE)
c = re.sub(r'^foreground = "#[0-9a-fA-F]{6}"', f'foreground = "{pri_hex}"', c, flags=re.MULTILINE)
c = re.sub(r'^selection = "#[0-9a-fA-F]{6}"', f'selection = "{sel_hex}"', c, flags=re.MULTILINE)
c = re.sub(r'^muted = "#[0-9a-fA-F]{6}"', f'muted = "{sec_hex}"', c, flags=re.MULTILINE)
c = re.sub(r'^bright_magenta = "#[0-9a-fA-F]{6}"', f'bright_magenta = "{sec_hex}"', c, flags=re.MULTILINE)
with open(colors_path, 'w', encoding='utf-8') as f:
    f.write(c)

# 2. Update ghostty.conf
with open(ghostty_path, 'r', encoding='utf-8') as f:
    g = f.read()
g = re.sub(r'^foreground = #[0-9a-fA-F]{6}', f'foreground = {pri_hex}', g, flags=re.MULTILINE)
g = re.sub(r'^selection-background = #[0-9a-fA-F]{6}', f'selection-background = {sel_hex}', g, flags=re.MULTILINE)
g = re.sub(r'^palette = 13=#[0-9a-fA-F]{6}', f'palette = 13={sec_hex}', g, flags=re.MULTILINE)
with open(ghostty_path, 'w', encoding='utf-8') as f:
    f.write(g)

# 3. Update hyprland.lua
with open(hypr_path, 'r', encoding='utf-8') as f:
    h = f.read()
h = re.sub(r'active_border_color = "rgb\([0-9a-fA-F]{6}\)"', f'active_border_color = "rgb({raw_pri})"', h)
h = re.sub(r'inactive_border_color = "rgb\([0-9a-fA-F]{6}\)"', f'inactive_border_color = "rgb({inactive_border})"', h)
with open(hypr_path, 'w', encoding='utf-8') as f:
    f.write(h)
EOF

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
if [ -f "${DOTS_DIR}/shell-patch/plugins/bar/BarModel.js" ]; then
  cp "${DOTS_DIR}/shell-patch/plugins/bar/BarModel.js" "${PLUGINS_DIR}/midnight-doll.bar/"
fi
cp "${DOTS_DIR}/shell-patch/plugins/bar/widgets/Workspaces.qml" "${PLUGINS_DIR}/midnight-doll.bar/widgets/"
python3 - "${PLUGINS_DIR}/midnight-doll.bar/Bar.qml" "${HUD_TITLE}" "${HUD_SUBTITLE}" "${HUD_CMD}" "${CHOSEN_SECONDARY}" "${MENU_GLYPH}" << 'EOF'
import sys, re
target_bar, title, subtitle, cmd, sec_color, glyph = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6]
with open(target_bar, 'r', encoding='utf-8') as f:
    c = f.read()
title_escaped = title.replace('\\', '\\\\').replace('"', '\\"')
sub_escaped = subtitle.replace('\\', '\\\\').replace('"', '\\"')
cmd_escaped = cmd.replace('\\', '\\\\').replace('"', '\\"')
sec_escaped = sec_color.replace('\\', '\\\\').replace('"', '\\"')
glyph_escaped = glyph.replace('\\', '\\\\').replace('"', '\\"')
c = re.sub(r'property string hudTitle: ".*?"', lambda m: f'property string hudTitle: "{title_escaped}"', c)
c = re.sub(r'property string hudSubtitle: ".*?"', lambda m: f'property string hudSubtitle: "{sub_escaped}"', c)
c = re.sub(r'property string hudCommand: ".*?"', lambda m: f'property string hudCommand: "{cmd_escaped}"', c)
c = re.sub(r'property color secondaryColor: ".*?"', lambda m: f'property color secondaryColor: "{sec_escaped}"', c)
c = re.sub(r'property string menuIcon: ".*?"', lambda m: f'property string menuIcon: "{glyph_escaped}"', c)
with open(target_bar, 'w', encoding='utf-8') as f:
    f.write(c)
EOF
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

# 4. System HUD widget (modular CPU, RAM, Disk, Network monitors)
mkdir -p "${PLUGINS_DIR}/midnight-doll.sys-hud"
cp -r "${DOTS_DIR}/shell-patch/plugins/sys-hud/"* "${PLUGINS_DIR}/midnight-doll.sys-hud/"

# 5. Visualizer widget (modular CAVA audio LED dot-matrix)
mkdir -p "${PLUGINS_DIR}/midnight-doll.visualizer"
cp -r "${DOTS_DIR}/shell-patch/plugins/visualizer/"* "${PLUGINS_DIR}/midnight-doll.visualizer/"

# Configure default midnightRight slot in shell.json if present
if [ -f "${HOME}/.config/omarchy/shell.json" ]; then
  python3 - "${HOME}/.config/omarchy/shell.json" << 'EOF'
import sys, json
shell_path = sys.argv[1]
try:
    with open(shell_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    bar = data.setdefault("bar", {})
    layout = bar.setdefault("layout", {})
    if "midnightRight" not in layout or not layout["midnightRight"]:
        layout["midnightRight"] = [
            {"id": "midnight-doll.sys-hud"},
            {"id": "midnight-doll.visualizer"}
        ]
        with open(shell_path, 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=2)
            f.write("\n")
except Exception:
    pass
EOF
fi

# Activate theme and plugins if omarchy CLI is available
if command -v omarchy &> /dev/null; then
  echo -e "${PINK}[*] Activating Midnight-Doll theme & cyberdeck bar...${RESET}"
  omarchy theme set "Midnight Doll" || true
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  omarchy bar use midnight-doll.bar || true
  omarchy plugin enable midnight-doll.workspaces || true
  omarchy plugin enable midnight-doll.clock || true
  omarchy plugin enable midnight-doll.sys-hud || true
  omarchy plugin enable midnight-doll.visualizer || true
  omarchy plugin enable omarchy.menu || true
  omarchy restart shell || true
fi

echo -e "\n${GREEN}${BOLD}✓ Midnight-Doll // Cyberdeck HUD successfully installed!${RESET}"
echo -e "    ${PINK}• Primary Accent:${RESET}       ${CHOSEN_PRIMARY}"
echo -e "    ${PINK}• Complimentary Accent:${RESET} ${CHOSEN_SECONDARY}"
if [ -n "$HUD_TITLE" ] && [ -n "$HUD_SUBTITLE" ]; then
  echo -e "    ${PINK}• HUD Header:${RESET}           ${HUD_TITLE} // ${HUD_SUBTITLE}"
elif [ -n "$HUD_SUBTITLE" ]; then
  echo -e "    ${PINK}• HUD Header:${RESET}           ${HUD_SUBTITLE}"
else
  echo -e "    ${PINK}• HUD Header:${RESET}           ${HUD_TITLE}"
fi
echo -e "    ${PINK}• HUD Action:${RESET}           ${HUD_CMD:-[Disabled]}"
echo -e "    ${PINK}• Menu Icon:${RESET}            ${MENU_GLYPH}"
echo -e "\n${PINK}Press Win+Space or inspect your top & left bars to explore.${RESET}"
echo -e "${VIOLET}To restore your previous setup at any time, run: ./uninstall.sh${RESET}\n"
