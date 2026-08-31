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

# 5. Backup Quickshell plugins
if [ -d "${OMARCHY_SHELL_DIR}" ]; then
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

if [ -d "${OMARCHY_SHELL_DIR}" ]; then
  echo -e "${VIOLET}[*] Deploying Shell Plugins & HUD Modules to ${OMARCHY_SHELL_DIR}...${RESET}"
  cp "${DOTS_DIR}/shell-patch/plugins/bar/Bar.qml" "${OMARCHY_SHELL_DIR}/plugins/bar/"
  cp "${DOTS_DIR}/shell-patch/plugins/bar/widgets/Workspaces.qml" "${OMARCHY_SHELL_DIR}/plugins/bar/widgets/"
  cp "${DOTS_DIR}/shell-patch/plugins/menu/BarWidget.qml" "${OMARCHY_SHELL_DIR}/plugins/menu/"
  cp "${DOTS_DIR}/shell-patch/plugins/panels/clock/BarWidget.qml" "${OMARCHY_SHELL_DIR}/plugins/panels/clock/"
fi

# Activate theme if omarchy CLI is available
if command -v omarchy &> /dev/null; then
  echo -e "${PINK}[*] Activating Midnight-Doll theme...${RESET}"
  omarchy theme set "Midnight Doll" || true
  omarchy restart shell || true
fi

echo -e "\n${GREEN}${BOLD}✓ Midnight-Doll // Cyberdeck HUD successfully installed!${RESET}"
echo -e "${PINK}Press Win+Space or inspect your top & left bars to explore.${RESET}"
echo -e "${VIOLET}To restore your previous setup at any time, run: ./uninstall.sh${RESET}\n"
