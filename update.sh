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

if [ -f "${OMARCHY_DIR}/shell.json" ]; then
  cp "${OMARCHY_DIR}/shell.json" "${BACKUP_DIR}/"
fi
echo -e "    ${GREEN}✓ Backup created at:${RESET} ${BACKUP_DIR}"

echo -e "\n${VIOLET}[*] Step 2: Deploying centralized theme directory & binaries...${RESET}"
mkdir -p "${THEME_DIR}/bin"

# Deploy theme configs
cp -r "${DOTS_DIR}/config/omarchy/themes/midnight-doll/"* "${THEME_DIR}/"
chmod +x "${THEME_DIR}/bin/"* 2>/dev/null || true

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

# Clean up legacy loose files from ~/.config/omarchy root
echo -e "\n${VIOLET}[*] Step 3: Cleaning up legacy un-namespaced files from ~/.config/omarchy/...${RESET}"
for loose in "cava.conf" "sys-hud.sh" "set-accent.sh" "launch-comms.sh" "midnight-shortcuts.json" "midnight-config.json"; do
  if [ -f "${OMARCHY_DIR}/${loose}" ]; then
    rm -f "${OMARCHY_DIR}/${loose}"
    echo -e "    ${CYAN}• Removed loose file:${RESET} ~/.config/omarchy/${loose}"
  fi
done

echo -e "\n${VIOLET}[*] Step 4: Ensuring clean QML environment (zero system shadows)...${RESET}"
rm -rf "${THEME_DIR}/qml"
rm -rf "${OMARCHY_DIR}/qml"
rm -f "${HOME}/.config/environment.d/qml.conf"
if [ -f "${HOME}/.config/hypr/autostart.lua" ]; then
  sed -i '/QML_IMPORT_PATH/d' "${HOME}/.config/hypr/autostart.lua"
fi
echo -e "    ${GREEN}✓ Pure stock Omarchy QML environment restored (no shadows)${RESET}"

echo -e "\n${VIOLET}[*] Step 5: Installing theme lifecycle hook (100% theme isolation)...${RESET}"
mkdir -p "${HOOKS_DIR}"
cp "${DOTS_DIR}/config/omarchy/hooks/theme-set.d/20-midnight-doll" "${HOOKS_DIR}/"
chmod +x "${HOOKS_DIR}/20-midnight-doll"
echo -e "    ${GREEN}✓ Installed lifecycle hook at:${RESET} ${HOOKS_DIR}/20-midnight-doll"

echo -e "\n${VIOLET}[*] Step 6: Updating Midnight-Doll Cyberdeck plugins...${RESET}"
# 1. Bar plugin
mkdir -p "${PLUGINS_DIR}/midnight-doll.bar"
cp "${DOTS_DIR}/shell-patch/plugins/bar/Bar.qml" "${PLUGINS_DIR}/midnight-doll.bar/"
if [ -f "${DOTS_DIR}/shell-patch/plugins/bar/BarModel.js" ]; then
  cp "${DOTS_DIR}/shell-patch/plugins/bar/BarModel.js" "${PLUGINS_DIR}/midnight-doll.bar/"
fi

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
echo -e "    ${PINK}• Switching:${RESET}    Switching themes automatically resets to stock Omarchy bar\n"
