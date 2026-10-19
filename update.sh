#!/usr/bin/env bash
set -e

# ==============================================================================
#  Midnight-Doll // Cyberdeck HUD - Updater & Sync Script
#  Safely updates Midnight-Doll to the latest isolated architecture:
#  - Migrates configs from legacy ~/.config/omarchy root into themes/midnight-doll/
#  - Preserves custom user shortcuts, colors, and configuration
#  - Deploys updated bar, modular plugins, and scoped QML overrides
#  - Installs theme-set lifecycle hook for 100% theme isolation
#  - Cleans up legacy loose files and restarts the shell
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
                         |___/      // UPDATER & SYNC
BANNER
echo -e "${RESET}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "")"
DOTS_DIR=""
TEMP_CLONE=""
SYNC_WALLPAPERS=false

for arg in "$@"; do
  case "$arg" in
    --force-wallpapers|--sync-wallpapers)
      SYNC_WALLPAPERS=true
      ;;
  esac
done

# Determine source repository directory
if [ -n "$SCRIPT_DIR" ] && [ -d "$SCRIPT_DIR/config/omarchy/themes/midnight-doll" ]; then
  DOTS_DIR="$SCRIPT_DIR"
  echo -e "${VIOLET}[*] Running from local repository:${RESET} ${DOTS_DIR}"
  if [ -d "$DOTS_DIR/.git" ]; then
    echo -e "${CYAN}[*] Checking for updates from GitHub...${RESET}"
    if git -C "$DOTS_DIR" diff --quiet 2>/dev/null; then
      git -C "$DOTS_DIR" pull --ff-only origin master 2>/dev/null || git -C "$DOTS_DIR" pull origin master 2>/dev/null || true
    else
      echo -e "${YELLOW}[!] Local modifications detected; skipping git pull.${RESET}"
    fi
  fi
else
  # If executed via curl/pipe, check common clone locations or clone to temp
  for loc in "${HOME}/Work/midnight-doll-dots" "${HOME}/midnight-doll-dots" "${HOME}/.local/share/midnight-doll-dots"; do
    if [ -d "$loc/.git" ]; then
      DOTS_DIR="$loc"
      echo -e "${VIOLET}[*] Found existing installation at:${RESET} ${DOTS_DIR}"
      git -C "$DOTS_DIR" pull origin master || true
      break
    fi
  done
  if [ -z "$DOTS_DIR" ]; then
    TEMP_CLONE=$(mktemp -d /tmp/midnight-doll-update-XXXXXX)
    echo -e "${CYAN}[*] Fetching latest release from GitHub to ${TEMP_CLONE}...${RESET}"
    git clone --depth=1 https://github.com/PunchManSam/midnight-doll-dots.git "$TEMP_CLONE"
    DOTS_DIR="$TEMP_CLONE"
  fi
fi

cleanup() {
  if [ -n "$TEMP_CLONE" ] && [ -d "$TEMP_CLONE" ]; then
    rm -rf "$TEMP_CLONE"
  fi
}
trap cleanup EXIT

OMARCHY_DIR="${HOME}/.config/omarchy"
THEME_DIR="${OMARCHY_DIR}/themes/midnight-doll"
PLUGINS_DIR="${OMARCHY_DIR}/plugins"
HOOKS_DIR="${OMARCHY_DIR}/hooks/theme-set.d"
BACKUP_DIR="${OMARCHY_DIR}/backups/midnight-doll-pre-update-$(date +%Y%m%d_%H%M%S)"

echo -e "\n${VIOLET}[*] Step 1: Backing up existing customizations...${RESET}"
mkdir -p "${BACKUP_DIR}"

# Preserve user launcher shortcuts
USER_SHORTCUTS=""
if [ -f "${THEME_DIR}/midnight-shortcuts.json" ]; then
  cp "${THEME_DIR}/midnight-shortcuts.json" "${BACKUP_DIR}/"
  USER_SHORTCUTS="${THEME_DIR}/midnight-shortcuts.json"
elif [ -f "${OMARCHY_DIR}/midnight-shortcuts.json" ]; then
  cp "${OMARCHY_DIR}/midnight-shortcuts.json" "${BACKUP_DIR}/"
  USER_SHORTCUTS="${OMARCHY_DIR}/midnight-shortcuts.json"
fi

# Preserve user midnight config (accents, sideBarPosition, etc.)
USER_CONFIG=""
if [ -f "${THEME_DIR}/midnight-config.json" ]; then
  cp "${THEME_DIR}/midnight-config.json" "${BACKUP_DIR}/"
  USER_CONFIG="${THEME_DIR}/midnight-config.json"
elif [ -f "${OMARCHY_DIR}/midnight-config.json" ]; then
  cp "${OMARCHY_DIR}/midnight-config.json" "${BACKUP_DIR}/"
  USER_CONFIG="${OMARCHY_DIR}/midnight-config.json"
fi

# Preserve user wallpapers if present in theme dir
if [ -d "${THEME_DIR}/backgrounds" ]; then
  mkdir -p "${BACKUP_DIR}/backgrounds"
  cp -r "${THEME_DIR}/backgrounds/"* "${BACKUP_DIR}/backgrounds/" 2>/dev/null || true
  echo -e "    ${GREEN}✓ Preserved existing wallpapers in backup${RESET}"
fi

if [ -f "${OMARCHY_DIR}/shell.json" ]; then
  cp "${OMARCHY_DIR}/shell.json" "${BACKUP_DIR}/"
fi
echo -e "    ${GREEN}✓ Backup created at:${RESET} ${BACKUP_DIR}"

echo -e "\n${VIOLET}[*] Step 2: Deploying centralized theme directory & binaries...${RESET}"
mkdir -p "${THEME_DIR}/bin"

## Deploy theme configs (preserving existing wallpapers unless missing or --force-wallpapers specified)
for item in "${DOTS_DIR}/config/omarchy/themes/midnight-doll/"*; do
  base="$(basename "$item")"
  if [ "$base" = "backgrounds" ]; then
    if [ "$SYNC_WALLPAPERS" = true ]; then
      echo -e "    ${CYAN}• Force-syncing wallpapers from repository...${RESET}"
      mkdir -p "${THEME_DIR}/backgrounds"
      cp -r "$item/"* "${THEME_DIR}/backgrounds/"
    elif [ ! -d "${THEME_DIR}/backgrounds" ] || [ -z "$(ls -A "${THEME_DIR}/backgrounds" 2>/dev/null)" ]; then
      echo -e "    ${CYAN}• Deploying initial bundled wallpapers...${RESET}"
      mkdir -p "${THEME_DIR}/backgrounds"
      cp -r "$item/"* "${THEME_DIR}/backgrounds/"
    else
      echo -e "    ${CYAN}• Preserving existing wallpapers in ${THEME_DIR}/backgrounds/ (skipping re-copy)${RESET}"
    fi
  else
    cp -r "$item" "${THEME_DIR}/"
  fi
done
chmod +x "${THEME_DIR}/bin/"* 2>/dev/null || true
# Strip .git from theme dir so Omarchy never treats it as an untrusted git clone
rm -rf "${THEME_DIR}/.git"

# Restore any custom wallpapers from backup if they were present
if [ -d "${BACKUP_DIR}/backgrounds" ]; then
  cp -rn "${BACKUP_DIR}/backgrounds/"* "${THEME_DIR}/backgrounds/" 2>/dev/null || true
fi

# Ensure user background folder exists for Omarchy
mkdir -p "${OMARCHY_DIR}/backgrounds/midnight-doll"

# Restore user shortcuts if backed up
if [ -f "${BACKUP_DIR}/midnight-shortcuts.json" ]; then
  cp "${BACKUP_DIR}/midnight-shortcuts.json" "${THEME_DIR}/midnight-shortcuts.json"
  echo -e "    ${GREEN}✓ Restored user launcher shortcuts${RESET}"
fi

# Restore user config if backed up
if [ -f "${BACKUP_DIR}/midnight-config.json" ]; then
  cp "${BACKUP_DIR}/midnight-config.json" "${THEME_DIR}/midnight-config.json"
  echo -e "    ${GREEN}✓ Restored user accent & layout configuration${RESET}"
fi

# Sync user accents to theme configs (colors.toml, ghostty.conf, kitty.conf, hyprland.lua)
if [ -f "${THEME_DIR}/midnight-config.json" ]; then
  python3 - "${THEME_DIR}/midnight-config.json" \
    "${THEME_DIR}/colors.toml" \
    "${THEME_DIR}/ghostty.conf" \
    "${THEME_DIR}/kitty.conf" \
    "${THEME_DIR}/hyprland.lua" << 'EOF'
import sys, json, os, re
cfg_path, colors_path, ghostty_path, kitty_path, hypr_path = sys.argv[1:6]
try:
    with open(cfg_path, 'r', encoding='utf-8') as f:
        cfg = json.load(f)
    pri_hex = cfg.get("primaryAccent", "#ff51c5").strip()
    sec_hex = cfg.get("secondaryAccent", "#bb9af7").strip()
    pr, pg, pb = int(pri_hex[1:3], 16), int(pri_hex[3:5], 16), int(pri_hex[5:7], 16)
    sel_hex = f"#{int(pr * 0.5):02x}{int(pg * 0.5):02x}{int(pb * 0.5):02x}"
    sr, sg, sb = int(sec_hex[1:3], 16), int(sec_hex[3:5], 16), int(sec_hex[5:7], 16)
    inactive_border = f"{int(sr * 0.22):02x}{int(sg * 0.22):02x}{int(sb * 0.22):02x}"
    raw_pri = pri_hex.lstrip('#')

    def update_colors(p):
        if not os.path.exists(p): return
        with open(p, 'r', encoding='utf-8') as f: c = f.read()
        c = re.sub(r'^accent = "#[0-9a-fA-F]{6}"', f'accent = "{pri_hex}"', c, flags=re.MULTILINE)
        c = re.sub(r'^selection = "#[0-9a-fA-F]{6}"', f'selection = "{sel_hex}"', c, flags=re.MULTILINE)
        c = re.sub(r'^muted = "#[0-9a-fA-F]{6}"', f'muted = "{sec_hex}"', c, flags=re.MULTILINE)
        c = re.sub(r'^magenta = "#[0-9a-fA-F]{6}"', f'magenta = "{pri_hex}"', c, flags=re.MULTILINE)
        c = re.sub(r'^bright_magenta = "#[0-9a-fA-F]{6}"', f'bright_magenta = "{sec_hex}"', c, flags=re.MULTILINE)
        if 'hyprland_active_border' in c:
            c = re.sub(r'^hyprland_active_border = ".*?"', f'hyprland_active_border = "rgb({raw_pri})"', c, flags=re.MULTILINE)
            c = re.sub(r'^hyprland_inactive_border = ".*?"', f'hyprland_inactive_border = "rgb({inactive_border})"', c, flags=re.MULTILINE)
        else:
            c += f'\nhyprland_active_border = "rgb({raw_pri})"\nhyprland_inactive_border = "rgb({inactive_border})"\n'
        with open(p, 'w', encoding='utf-8') as f: f.write(c)

    def update_ghostty(p):
        if not os.path.exists(p): return
        with open(p, 'r', encoding='utf-8') as f: g = f.read()
        g = re.sub(r'^selection-background = #[0-9a-fA-F]{6}', f'selection-background = {sel_hex}', g, flags=re.MULTILINE)
        g = re.sub(r'^palette = 5=#[0-9a-fA-F]{6}', f'palette = 5={pri_hex}', g, flags=re.MULTILINE)
        g = re.sub(r'^palette = 13=#[0-9a-fA-F]{6}', f'palette = 13={sec_hex}', g, flags=re.MULTILINE)
        with open(p, 'w', encoding='utf-8') as f: f.write(g)

    def update_kitty(p):
        if not os.path.exists(p): return
        with open(p, 'r', encoding='utf-8') as f: k = f.read()
        k = re.sub(r'^selection_background #[0-9a-fA-F]{6}', f'selection_background {sel_hex}', k, flags=re.MULTILINE)
        k = re.sub(r'^active_border_color #[0-9a-fA-F]{6}', f'active_border_color {pri_hex}', k, flags=re.MULTILINE)
        k = re.sub(r'^active_tab_background #[0-9a-fA-F]{6}', f'active_tab_background {pri_hex}', k, flags=re.MULTILINE)
        k = re.sub(r'^color5 #[0-9a-fA-F]{6}', f'color5 {pri_hex}', k, flags=re.MULTILINE)
        k = re.sub(r'^color13 #[0-9a-fA-F]{6}', f'color13 {sec_hex}', k, flags=re.MULTILINE)
        with open(p, 'w', encoding='utf-8') as f: f.write(k)

    def update_hypr(p):
        if not os.path.exists(p): return
        with open(p, 'r', encoding='utf-8') as f: h = f.read()
        h = re.sub(r'active_border_color = "rgb\([0-9a-fA-F]{6}\)"', f'active_border_color = "rgb({raw_pri})"', h)
        h = re.sub(r'inactive_border_color = "rgb\([0-9a-fA-F]{6}\)"', f'inactive_border_color = "rgb({inactive_border})"', h)
        if 'QML_IMPORT_PATH' not in h:
            h = '-- Ensure Quickshell inherits QML_IMPORT_PATH for Midnight Doll\'s shelf drawer panels\nhl.env("QML_IMPORT_PATH", (os.getenv("HOME") or "") .. "/.config/omarchy/themes/midnight-doll/qml")\n\n' + h
        with open(p, 'w', encoding='utf-8') as f: f.write(h)

    update_colors(colors_path)
    update_ghostty(ghostty_path)
    update_kitty(kitty_path)
    update_hypr(hypr_path)

    home = os.path.expanduser("~")
    update_colors(os.path.join(home, ".local/state/omarchy/current/theme/colors.toml"))
    update_ghostty(os.path.join(home, ".local/state/omarchy/current/theme/ghostty.conf"))
    update_kitty(os.path.join(home, ".local/state/omarchy/current/theme/kitty.conf"))
    update_hypr(os.path.join(home, ".local/state/omarchy/current/theme/hyprland.lua"))
except Exception:
    pass
EOF
fi

# Clean up legacy loose files from ~/.config/omarchy root
echo -e "\n${VIOLET}[*] Step 3: Cleaning up legacy un-namespaced files from ~/.config/omarchy/...${RESET}"
for loose in "cava.conf" "sys-hud.sh" "set-accent.sh" "launch-comms.sh" "midnight-shortcuts.json" "midnight-config.json"; do
  if [ -f "${OMARCHY_DIR}/${loose}" ]; then
    rm -f "${OMARCHY_DIR}/${loose}"
    echo -e "    ${CYAN}• Removed loose file:${RESET} ~/.config/omarchy/${loose}"
  fi
done

echo -e "\n${VIOLET}[*] Step 4: Deploying scoped QML shelf drawer overrides...${RESET}"
QML_OVERRIDE_DIR="${THEME_DIR}/qml"
mkdir -p "${QML_OVERRIDE_DIR}/qs/Ui"
ln -sfn "/usr/share/omarchy/shell/Commons" "${QML_OVERRIDE_DIR}/qs/Commons"
if [ -d "/usr/share/omarchy/shell/Ui" ]; then
  for f in /usr/share/omarchy/shell/Ui/*.qml; do
    base="$(basename "$f")"
    if [ "$base" != "KeyboardPanel.qml" ] && [ "$base" != "PopupCard.qml" ]; then
      ln -sfn "$f" "${QML_OVERRIDE_DIR}/qs/Ui/${base}"
    fi
  done
fi
if [ -f "/usr/share/omarchy/shell/Ui/qmldir" ]; then
  cp "/usr/share/omarchy/shell/Ui/qmldir" "${QML_OVERRIDE_DIR}/qs/Ui/qmldir"
else
  cp "${DOTS_DIR}/shell-patch/qml/qs/Ui/qmldir" "${QML_OVERRIDE_DIR}/qs/Ui/"
fi
cp "${DOTS_DIR}/shell-patch/qml/qs/Ui/KeyboardPanel.qml" "${QML_OVERRIDE_DIR}/qs/Ui/"
cp "${DOTS_DIR}/shell-patch/qml/qs/Ui/PopupCard.qml" "${QML_OVERRIDE_DIR}/qs/Ui/"

# Remove legacy global ~/.config/omarchy/qml if present
rm -rf "${OMARCHY_DIR}/qml"

# Configure QML_IMPORT_PATH and live inject into Hyprland & systemd
mkdir -p "${HOME}/.config/environment.d"
echo "QML_IMPORT_PATH=${QML_OVERRIDE_DIR}" > "${HOME}/.config/environment.d/qml.conf"
if [ -f "${HOME}/.config/hypr/autostart.lua" ]; then
  sed -i '/QML_IMPORT_PATH/d' "${HOME}/.config/hypr/autostart.lua"
  sed -i '1i hl.env("QML_IMPORT_PATH", (os.getenv("HOME") or "'"${HOME}"'") .. "/.config/omarchy/themes/midnight-doll/qml")' "${HOME}/.config/hypr/autostart.lua"
fi

# Fetch active accents for live Hyprland styling
PRI_HEX=$(python3 -c "import json; print(json.load(open('${THEME_DIR}/midnight-config.json')).get('primaryAccent', '#ff51c5'))" 2>/dev/null || echo "#ff51c5")
SEC_HEX=$(python3 -c "import json; print(json.load(open('${THEME_DIR}/midnight-config.json')).get('secondaryAccent', '#bb9af7'))" 2>/dev/null || echo "#bb9af7")
RAW_PRI="${PRI_HEX#\#}"
INACTIVE_BORDER=$(python3 -c "s='$SEC_HEX'.lstrip('#'); sr,sg,sb=int(s[0:2],16),int(s[2:4],16),int(s[4:6],16); print(f'{int(sr*0.22):02x}{int(sg*0.22):02x}{int(sb*0.22):02x}')" 2>/dev/null || echo "292136")

if command -v hyprctl &>/dev/null; then
  hyprctl eval 'hl.env("QML_IMPORT_PATH", "'"${QML_OVERRIDE_DIR}"'")' >/dev/null 2>&1 || true
  hyprctl eval 'hl.config({ general = { gaps_in = 0, gaps_out = 0, border_size = 2, col = { active_border = "rgb('"${RAW_PRI}"')", inactive_border = "rgb('"${INACTIVE_BORDER}"')" } }, decoration = { rounding = 0 } })' >/dev/null 2>&1 || true
  hyprctl reload >/dev/null 2>&1 || true
fi
if command -v systemctl &>/dev/null; then
  systemctl --user set-environment QML_IMPORT_PATH="${QML_OVERRIDE_DIR}" 2>/dev/null || true
  systemctl --user import-environment QML_IMPORT_PATH 2>/dev/null || true
fi
export QML_IMPORT_PATH="${QML_OVERRIDE_DIR}"
echo -e "    ${GREEN}✓ Attached shelf drawers & drawer animations deployed${RESET}"

echo -e "\n${VIOLET}[*] Step 5: Installing theme lifecycle hook (100% theme isolation)...${RESET}"
mkdir -p "${HOOKS_DIR}"
cp "${DOTS_DIR}/config/omarchy/hooks/theme-set.d/20-midnight-doll" "${HOOKS_DIR}/"
chmod +x "${HOOKS_DIR}/20-midnight-doll"
echo -e "    ${GREEN}✓ Installed lifecycle hook at:${RESET} ${HOOKS_DIR}/20-midnight-doll"

echo -e "\n${VIOLET}[*] Step 6: Updating Midnight-Doll Cyberdeck plugins...${RESET}"
# 1. Bar plugin
mkdir -p "${PLUGINS_DIR}/midnight-doll.bar"
cp -r "${DOTS_DIR}/shell-patch/plugins/bar/"* "${PLUGINS_DIR}/midnight-doll.bar/"

# 2. Sys-hud plugin
mkdir -p "${PLUGINS_DIR}/midnight-doll.sys-hud"
cp -r "${DOTS_DIR}/shell-patch/plugins/sys-hud/"* "${PLUGINS_DIR}/midnight-doll.sys-hud/"
chmod +x "${PLUGINS_DIR}/midnight-doll.sys-hud/sys-hud.sh" 2>/dev/null || true

# 3. Visualizer plugin
mkdir -p "${PLUGINS_DIR}/midnight-doll.visualizer"
cp -r "${DOTS_DIR}/shell-patch/plugins/visualizer/"* "${PLUGINS_DIR}/midnight-doll.visualizer/"

# 4. Notifications plugin
if [ -d "${DOTS_DIR}/shell-patch/plugins/notifications" ]; then
  mkdir -p "${PLUGINS_DIR}/midnight-doll.notifications"
  cp -r "${DOTS_DIR}/shell-patch/plugins/notifications/"* "${PLUGINS_DIR}/midnight-doll.notifications/"
  chmod +x "${PLUGINS_DIR}/midnight-doll.notifications/helper.py" 2>/dev/null || true
fi



# 5. Safe layout synchronization in shell.json
if [ -f "${HOME}/.config/omarchy/shell.json" ]; then
  python3 - "${HOME}/.config/omarchy/shell.json" << 'EOF'
import sys, json

shell_path = sys.argv[1]
try:
    with open(shell_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    bar = data.setdefault("bar", {})
    bar["id"] = "midnight-doll.bar"
    layout = bar.setdefault("layout", {})

    def get_id(item):
        if isinstance(item, dict): return item.get("id", "")
        return str(item) if item else ""

    raw_mr = layout.get("midnightRight")
    if not isinstance(raw_mr, list) or not raw_mr:
        layout["midnightRight"] = [
            {"id": "midnight-doll.sys-hud"},
            {"id": "midnight-doll.visualizer"}
        ]
    plugins = data.setdefault("plugins", [])
    seen_plugins = {get_id(p) for p in plugins}
    for req_p in ["midnight-doll.notifications", "midnight-doll.sys-hud", "midnight-doll.visualizer"]:
        if req_p not in seen_plugins:
            plugins.append({"id": req_p})
            seen_plugins.add(req_p)

    with open(shell_path, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2)
        f.write("\n")
except Exception:
    pass
EOF
fi

echo -e "\n${VIOLET}[*] Step 7: Rescanning plugins and hot-reloading shell...${RESET}"
if command -v omarchy-shell &>/dev/null; then
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
fi
if command -v omarchy &>/dev/null; then
  # Re-apply theme, enable plugins, and ensure custom bar is active
  omarchy theme set "Midnight Doll" >/dev/null 2>&1 || true
  omarchy plugin enable midnight-doll.bar >/dev/null 2>&1 || true
  omarchy plugin enable midnight-doll.notifications >/dev/null 2>&1 || true
  omarchy plugin enable midnight-doll.sys-hud >/dev/null 2>&1 || true
  omarchy plugin enable midnight-doll.visualizer >/dev/null 2>&1 || true
  omarchy bar use midnight-doll.bar >/dev/null 2>&1 || true
  omarchy restart shell >/dev/null 2>&1 || true
fi

echo -e "\n${GREEN}${BOLD}✓ Midnight-Doll successfully updated to the latest isolated architecture!${RESET}"
echo -e "    ${PINK}• Architecture:${RESET} 100% theme-isolated; zero root config pollution"
echo -e "    ${PINK}• Updates:${RESET}      System packages ('omarchy update') remain 100% safe"
echo -e "    ${PINK}• Switching:${RESET}    Switching themes automatically resets to stock Omarchy bar"
echo -e "    ${PINK}• Wallpapers:${RESET}   Preserved existing wallpapers; custom wallpapers go in:"
echo -e "                    ${CYAN}~/.config/omarchy/backgrounds/midnight-doll/${RESET}"
echo -e "                    (Run 'omarchy theme bg install' to open folder)\n"
