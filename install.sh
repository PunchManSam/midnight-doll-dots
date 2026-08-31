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

echo -e "${VIOLET}[*] Checking environment & dependencies...${RESET}"

# Check for CAVA
if ! command -v cava &> /dev/null; then
  echo -e "${CYAN}[i] Note: 'cava' audio visualizer was not found in PATH.${RESET}"
  echo -e "    Install cava via your package manager (e.g. 'sudo pacman -S cava' or 'yay -S cava') for audio spectrum support."
fi

# Check for omarchy
if ! command -v omarchy &> /dev/null; then
  echo -e "${VIOLET}[!] Warning: 'omarchy' CLI not detected in PATH. Proceeding with file deployment...${RESET}"
fi

# Create backup directory
mkdir -p "${BACKUP_DIR}"
echo -e "${VIOLET}[*] Created backup directory at: ${BACKUP_DIR}${RESET}"

# Backup existing files if they exist
if [ -d "${HOME}/.config/omarchy/themes/midnight-doll" ]; then
  cp -r "${HOME}/.config/omarchy/themes/midnight-doll" "${BACKUP_DIR}/" 2>/dev/null || true
fi
if [ -f "${HOME}/.config/omarchy/sys-hud.sh" ]; then
  cp "${HOME}/.config/omarchy/sys-hud.sh" "${BACKUP_DIR}/" 2>/dev/null || true
fi
if [ -f "${HOME}/.config/omarchy/cava.conf" ]; then
  cp "${HOME}/.config/omarchy/cava.conf" "${BACKUP_DIR}/" 2>/dev/null || true
fi
if [ -d "${OMARCHY_SHELL_DIR}" ]; then
  mkdir -p "${BACKUP_DIR}/shell-plugins"
  cp -r "${OMARCHY_SHELL_DIR}/plugins/bar" "${BACKUP_DIR}/shell-plugins/" 2>/dev/null || true
  cp -r "${OMARCHY_SHELL_DIR}/plugins/menu" "${BACKUP_DIR}/shell-plugins/" 2>/dev/null || true
  cp -r "${OMARCHY_SHELL_DIR}/plugins/panels/clock" "${BACKUP_DIR}/shell-plugins/" 2>/dev/null || true
fi

echo -e "${VIOLET}[*] Deploying Theme & Scripts to ~/.config/omarchy/...${RESET}"
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
echo -e "${PINK}Press Win+Space or inspect your top & left bars to explore.${RESET}\n"
