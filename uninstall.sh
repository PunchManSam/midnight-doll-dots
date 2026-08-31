#!/usr/bin/env bash
set -e

# ==============================================================================
#  Midnight-Doll // Rollback & Restore Script
# ==============================================================================

BOLD="\033[1m"
VIOLET="\033[38;2;187;154;247m"
GREEN="\033[32m"
RESET="\033[0m"

BACKUP_ROOT="${HOME}/.config/omarchy/backups"

echo -e "${VIOLET}${BOLD}[*] Looking for latest Midnight-Doll backup...${RESET}"

if [ ! -d "${BACKUP_ROOT}" ]; then
  echo "No backups directory found at ${BACKUP_ROOT}."
  exit 1
fi

LATEST_BACKUP="$(ls -td "${BACKUP_ROOT}"/midnight-doll-* 2>/dev/null | head -n 1 || true)"

if [ -z "${LATEST_BACKUP}" ] || [ ! -d "${LATEST_BACKUP}" ]; then
  echo "No previous backup found to restore."
  exit 1
fi

echo -e "${VIOLET}[*] Restoring from backup: ${LATEST_BACKUP}${RESET}"

if [ -d "${LATEST_BACKUP}/midnight-doll" ]; then
  rm -rf "${HOME}/.config/omarchy/themes/midnight-doll"
  cp -r "${LATEST_BACKUP}/midnight-doll" "${HOME}/.config/omarchy/themes/"
fi

if [ -f "${LATEST_BACKUP}/sys-hud.sh" ]; then
  cp "${LATEST_BACKUP}/sys-hud.sh" "${HOME}/.config/omarchy/"
fi

if [ -d "${LATEST_BACKUP}/shell-plugins" ] && [ -d "${HOME}/omarchy/shell" ]; then
  cp -r "${LATEST_BACKUP}/shell-plugins/"* "${HOME}/omarchy/shell/plugins/"
fi

if command -v omarchy &> /dev/null; then
  omarchy restart shell || true
fi

echo -e "${GREEN}${BOLD}✓ System restored to pre-Midnight-Doll backup state.${RESET}"
