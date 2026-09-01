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
OMARCHY_SHELL_DIR="${HOME}/omarchy/shell"

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

# Check for CAVA
if ! command -v cava &> /dev/null; then
  echo -e "${YELLOW}[!] Note: 'cava' audio visualizer was not found in PATH.${RESET}"
  echo -e "    Install cava via your package manager (e.g. 'sudo pacman -S cava' or 'yay -S cava') for live audio spectrum support."
fi

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

# 5. Backup Quickshell plugins (dev checkout only)
CAN_PATCH_DEV_SHELL=false
if [ -d "${OMARCHY_SHELL_DIR}" ] && [ -w "${OMARCHY_SHELL_DIR}/plugins/bar" ]; then
  RESOLVED_SHELL="$(realpath "${OMARCHY_SHELL_DIR}" 2>/dev/null || true)"
  if [[ -n "${RESOLVED_SHELL}" && "${RESOLVED_SHELL}" != "/usr/share/omarchy"* ]]; then
    CAN_PATCH_DEV_SHELL=true
  fi
fi

if [ "$CAN_PATCH_DEV_SHELL" = true ]; then
  mkdir -p "${BACKUP_DIR}/shell-plugins"
  for plugin in "bar" "menu" "panels/clock"; do
    if [ -d "${OMARCHY_SHELL_DIR}/plugins/${plugin}" ]; then
      mkdir -p "${BACKUP_DIR}/shell-plugins/$(dirname "${plugin}")"
      cp -r "${OMARCHY_SHELL_DIR}/plugins/${plugin}" "${BACKUP_DIR}/shell-plugins/$(dirname "${plugin}")/"
      echo -e "    ✓ Backed up shell plugin: ${plugin}"
    fi
  done
fi

# 6. Generate detailed backup manifest
cat << MANIFEST > "${BACKUP_DIR}/backup_manifest.json"
{
  "timestamp": "$(date -Iseconds 2>/dev/null || date)",
  "original_theme": "${ACTIVE_THEME}",
  "user": "${USER}",
  "backup_dir": "${BACKUP_DIR}"
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

# 3. Menu widget (Nerd Font Skull launcher)
mkdir -p "${PLUGINS_DIR}/midnight-doll.menu"
if [ -d "${OMARCHY_SYS_PLUGINS}/menu" ]; then
  cp -r "${OMARCHY_SYS_PLUGINS}/menu/"* "${PLUGINS_DIR}/midnight-doll.menu/" 2>/dev/null || true
fi
cp "${DOTS_DIR}/shell-patch/plugins/menu/BarWidget.qml" "${PLUGINS_DIR}/midnight-doll.menu/"
cat << 'EOF' > "${PLUGINS_DIR}/midnight-doll.menu/manifest.json"
{
  "schemaVersion": 1,
  "id": "midnight-doll.menu",
  "name": "Midnight Doll Menu",
  "version": "1.0.0",
  "author": "Midnight Doll",
  "description": "Cyberdeck Skull Menu Launcher",
  "kinds": [
    "menu",
    "bar-widget"
  ],
  "keepLoaded": true,
  "entryPoints": {
    "menu": "Menu.qml",
    "barWidget": "BarWidget.qml"
  },
  "barWidget": {
    "displayName": "Midnight Doll Menu",
    "description": "Cyberdeck Skull Menu Launcher",
    "category": "Compositor",
    "allowMultiple": false
  },
  "omarchy": {
    "clonedFrom": "omarchy.menu"
  }
}
EOF

# 4. Clock widget (military uppercase format)
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
  omarchy plugin enable midnight-doll.menu || true
  omarchy plugin enable midnight-doll.clock || true
  omarchy restart shell || true
fi

echo -e "\n${GREEN}${BOLD}✓ Midnight-Doll // Cyberdeck HUD successfully installed!${RESET}"
echo -e "${PINK}Press Win+Space or inspect your top & left bars to explore.${RESET}"
echo -e "${VIOLET}To restore your previous setup at any time, run: ./uninstall.sh${RESET}\n"
