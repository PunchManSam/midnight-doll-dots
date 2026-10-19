#!/usr/bin/env bash
set -e

# ==============================================================================
#  Midnight-Doll // Live Accent Color Switcher
#
#  Usage:
#    set-accent.sh <primary_color> [complimentary_color]
#
#  Examples:
#    set-accent.sh #ff007f
#    set-accent.sh #39ff14 #da14ff
#    set-accent.sh cyan purple
# ==============================================================================

BOLD="\033[1m"
PINK="\033[38;2;255;81;197m"
VIOLET="\033[38;2;187;154;247m"
GREEN="\033[32m"
YELLOW="\033[33m"
RESET="\033[0m"

if [ -z "$1" ]; then
  echo -e "${YELLOW}Usage: set-accent.sh <primary_hex_or_name> [complimentary_hex_or_name]${RESET}"
  echo -e "Examples:"
  echo -e "  set-accent.sh #ff007f"
  echo -e "  set-accent.sh #00ff9f #00f0ff"
  echo -e "  set-accent.sh cyan purple"
  exit 1
fi

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

PRIMARY="$(normalize_color "$1" "")"
if [ -z "$PRIMARY" ]; then
  echo -e "${YELLOW}[!] Invalid primary color: $1${RESET}"
  exit 1
fi

if [ -n "$2" ]; then
  SECONDARY="$(normalize_color "$2" "")"
  if [ -z "$SECONDARY" ]; then
    SECONDARY="$(calc_complement "$PRIMARY")"
  fi
else
  case "$PRIMARY" in
    "#ff51c5") SECONDARY="#bb9af7" ;;
    "#00ff9f") SECONDARY="#00f0ff" ;;
    "#ff3366") SECONDARY="#00f0ff" ;;
    "#00f0ff") SECONDARY="#ff51c5" ;;
    "#bb9af7") SECONDARY="#00f0ff" ;;
    "#ffe600") SECONDARY="#bb9af7" ;;
    "#ff8800") SECONDARY="#00f0ff" ;;
    *) SECONDARY="$(calc_complement "$PRIMARY")" ;;
  esac
fi

echo -e "${VIOLET}[*] Applying Accent Colors:${RESET}"
echo -e "    ${PINK}• Primary Accent:${RESET}       ${BOLD}${PRIMARY}${RESET}"
echo -e "    ${PINK}• Complimentary Accent:${RESET} ${BOLD}${SECONDARY}${RESET}"

# 1. Update theme configs
python3 - "${HOME}/.config/omarchy/themes/midnight-doll/colors.toml" \
  "${HOME}/.config/omarchy/themes/midnight-doll/ghostty.conf" \
  "${HOME}/.config/omarchy/themes/midnight-doll/kitty.conf" \
  "${HOME}/.config/omarchy/themes/midnight-doll/hyprland.lua" \
  "${PRIMARY}" \
  "${SECONDARY}" << 'EOF'
import sys, os, re
colors_path, ghostty_path, kitty_path, hypr_path = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
pri_hex, sec_hex = sys.argv[5].strip(), sys.argv[6].strip()

try:
    pr, pg, pb = int(pri_hex[1:3], 16), int(pri_hex[3:5], 16), int(pri_hex[5:7], 16)
    sel_hex = f"#{int(pr * 0.5):02x}{int(pg * 0.5):02x}{int(pb * 0.5):02x}"
except Exception:
    sel_hex = "#7f2862"

try:
    sr, sg, sb = int(sec_hex[1:3], 16), int(sec_hex[3:5], 16), int(sec_hex[5:7], 16)
    inactive_border = f"{int(sr * 0.22):02x}{int(sg * 0.22):02x}{int(sb * 0.22):02x}"
except Exception:
    inactive_border = "2b0938"

raw_pri = pri_hex.lstrip('#')

def update_colors_file(path):
    if not os.path.exists(path): return
    with open(path, 'r', encoding='utf-8') as f:
        c = f.read()
    c = re.sub(r'^accent = "#[0-9a-fA-F]{6}"', f'accent = "{pri_hex}"', c, flags=re.MULTILINE)
    c = re.sub(r'^foreground = "#[0-9a-fA-F]{6}"', 'foreground = "#d0d0d0"', c, flags=re.MULTILINE)
    c = re.sub(r'^dark_foreground = "#[0-9a-fA-F]{6}"', 'dark_foreground = "#767676"', c, flags=re.MULTILINE)
    c = re.sub(r'^light_foreground = "#[0-9a-fA-F]{6}"', 'light_foreground = "#ebebeb"', c, flags=re.MULTILINE)
    c = re.sub(r'^bright_foreground = "#[0-9a-fA-F]{6}"', 'bright_foreground = "#ffffff"', c, flags=re.MULTILINE)
    c = re.sub(r'^selection = "#[0-9a-fA-F]{6}"', f'selection = "{sel_hex}"', c, flags=re.MULTILINE)
    c = re.sub(r'^muted = "#[0-9a-fA-F]{6}"', f'muted = "{sec_hex}"', c, flags=re.MULTILINE)
    c = re.sub(r'^magenta = "#[0-9a-fA-F]{6}"', f'magenta = "{pri_hex}"', c, flags=re.MULTILINE)
    c = re.sub(r'^bright_magenta = "#[0-9a-fA-F]{6}"', f'bright_magenta = "{sec_hex}"', c, flags=re.MULTILINE)
    if 'hyprland_active_border' in c:
        c = re.sub(r'^hyprland_active_border = ".*?"', f'hyprland_active_border = "rgb({raw_pri})"', c, flags=re.MULTILINE)
        c = re.sub(r'^hyprland_inactive_border = ".*?"', f'hyprland_inactive_border = "rgb({inactive_border})"', c, flags=re.MULTILINE)
    else:
        c += f'\nhyprland_active_border = "rgb({raw_pri})"\nhyprland_inactive_border = "rgb({inactive_border})"\n'
    with open(path, 'w', encoding='utf-8') as f:
        f.write(c)

def update_ghostty_file(path):
    if not os.path.exists(path): return
    with open(path, 'r', encoding='utf-8') as f:
        g = f.read()
    g = re.sub(r'^foreground = #[0-9a-fA-F]{6}', 'foreground = #d0d0d0', g, flags=re.MULTILINE)
    g = re.sub(r'^selection-background = #[0-9a-fA-F]{6}', f'selection-background = {sel_hex}', g, flags=re.MULTILINE)
    g = re.sub(r'^palette = 5=#[0-9a-fA-F]{6}', f'palette = 5={pri_hex}', g, flags=re.MULTILINE)
    g = re.sub(r'^palette = 13=#[0-9a-fA-F]{6}', f'palette = 13={sec_hex}', g, flags=re.MULTILINE)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(g)

def update_kitty_file(path):
    if not os.path.exists(path): return
    with open(path, 'r', encoding='utf-8') as f:
        k = f.read()
    k = re.sub(r'^foreground #[0-9a-fA-F]{6}', 'foreground #d0d0d0', k, flags=re.MULTILINE)
    k = re.sub(r'^selection_background #[0-9a-fA-F]{6}', f'selection_background {sel_hex}', k, flags=re.MULTILINE)
    k = re.sub(r'^active_border_color #[0-9a-fA-F]{6}', f'active_border_color {pri_hex}', k, flags=re.MULTILINE)
    k = re.sub(r'^active_tab_background #[0-9a-fA-F]{6}', f'active_tab_background {pri_hex}', k, flags=re.MULTILINE)
    k = re.sub(r'^color5 #[0-9a-fA-F]{6}', f'color5 {pri_hex}', k, flags=re.MULTILINE)
    k = re.sub(r'^color13 #[0-9a-fA-F]{6}', f'color13 {sec_hex}', k, flags=re.MULTILINE)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(k)

def update_hyprland_file(path):
    if not os.path.exists(path): return
    with open(path, 'r', encoding='utf-8') as f:
        h = f.read()
    h = re.sub(r'active_border_color = "rgb\([0-9a-fA-F]{6}\)"', f'active_border_color = "rgb({raw_pri})"', h)
    h = re.sub(r'inactive_border_color = "rgb\([0-9a-fA-F]{6}\)"', f'inactive_border_color = "rgb({inactive_border})"', h)
    if 'QML_IMPORT_PATH' not in h:
        h = '-- Ensure Quickshell inherits QML_IMPORT_PATH for Midnight Doll\'s shelf drawer panels\nhl.env("QML_IMPORT_PATH", (os.getenv("HOME") or "") .. "/.config/omarchy/themes/midnight-doll/qml")\n\n' + h
    with open(path, 'w', encoding='utf-8') as f:
        f.write(h)

# 1. Update theme directory files
update_colors_file(colors_path)
update_ghostty_file(ghostty_path)
update_kitty_file(kitty_path)
update_hyprland_file(hypr_path)

# Also update active state copies if present
home = os.path.expanduser("~")
update_colors_file(os.path.join(home, ".local/state/omarchy/current/theme/colors.toml"))
update_ghostty_file(os.path.join(home, ".local/state/omarchy/current/theme/ghostty.conf"))
update_kitty_file(os.path.join(home, ".local/state/omarchy/current/theme/kitty.conf"))
update_hyprland_file(os.path.join(home, ".local/state/omarchy/current/theme/hyprland.lua"))
EOF

# Ensure theme directory has no .git to prevent Omarchy from treating it as an untrusted git theme
rm -rf "${HOME}/.config/omarchy/themes/midnight-doll/.git"

# 2. Update Bar.qml
BAR_QML="${HOME}/.config/omarchy/plugins/midnight-doll.bar/Bar.qml"
if [ -f "${BAR_QML}" ]; then
  python3 - "${BAR_QML}" "${SECONDARY}" << 'EOF'
import sys, re
bar_path, sec_color = sys.argv[1], sys.argv[2]
with open(bar_path, 'r', encoding='utf-8') as f:
    c = f.read()
sec_escaped = sec_color.replace('\\', '\\\\').replace('"', '\\"')
c = re.sub(r'property color secondaryColor: ".*?"', lambda m: f'property color secondaryColor: "{sec_escaped}"', c)
with open(bar_path, 'w', encoding='utf-8') as f:
    f.write(c)
EOF
fi

# 3. Update midnight-config.json
MIDNIGHT_CFG="${HOME}/.config/omarchy/themes/midnight-doll/midnight-config.json"
if [ ! -f "${MIDNIGHT_CFG}" ] && [ -f "${HOME}/.config/omarchy/midnight-config.json" ]; then
  MIDNIGHT_CFG="${HOME}/.config/omarchy/midnight-config.json"
fi
if [ -f "${MIDNIGHT_CFG}" ]; then
  python3 - "${MIDNIGHT_CFG}" "${PRIMARY}" "${SECONDARY}" << 'EOF'
import sys, json
cfg_path, pri, sec = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(cfg_path, 'r', encoding='utf-8') as f:
        cfg = json.load(f)
    cfg["primaryAccent"] = pri
    cfg["secondaryAccent"] = sec
    with open(cfg_path, 'w', encoding='utf-8') as f:
        json.dump(cfg, f, indent=2)
except Exception:
    pass
EOF
fi

# 4. Live injection of QML_IMPORT_PATH and Hyprland border colors & 0 gaps
RAW_PRI="${PRIMARY#\#}"
INACTIVE_BORDER=$(python3 -c "s='$SECONDARY'.lstrip('#'); sr,sg,sb=int(s[0:2],16),int(s[2:4],16),int(s[4:6],16); print(f'{int(sr*0.22):02x}{int(sg*0.22):02x}{int(sb*0.22):02x}')" 2>/dev/null || echo "292136")
QML_OVERRIDE_DIR="${HOME}/.config/omarchy/themes/midnight-doll/qml"

if command -v hyprctl &>/dev/null; then
  hyprctl eval 'hl.env("QML_IMPORT_PATH", "'"${QML_OVERRIDE_DIR}"'")' >/dev/null 2>&1 || true
  hyprctl eval 'hl.config({ general = { gaps_in = 0, gaps_out = 0, border_size = 2, col = { active_border = "rgb('"${RAW_PRI}"')", inactive_border = "rgb('"${INACTIVE_BORDER}"')" } }, decoration = { rounding = 0 } })' >/dev/null 2>&1 || true
  hyprctl reload >/dev/null 2>&1 || true
fi

if command -v systemctl &>/dev/null; then
  systemctl --user set-environment QML_IMPORT_PATH="${QML_OVERRIDE_DIR}" 2>/dev/null || true
  systemctl --user import-environment QML_IMPORT_PATH 2>/dev/null || true
fi

if command -v omarchy &> /dev/null; then
  omarchy theme set "Midnight Doll" >/dev/null 2>&1 || true
  omarchy restart shell >/dev/null 2>&1 || true
fi

echo -e "${GREEN}${BOLD}✓ Accent colors updated live!${RESET}"
