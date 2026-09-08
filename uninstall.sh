#!/usr/bin/env bash
set -e

# ==============================================================================
#  Midnight-Doll // Rollback & Restore Script
# ==============================================================================

BOLD="\033[1m"
PINK="\033[38;2;255;81;197m"
VIOLET="\033[38;2;187;154;247m"
GREEN="\033[32m"
YELLOW="\033[33m"
RESET="\033[0m"

BACKUP_ROOT="${HOME}/.config/omarchy/backups"

echo -e "${VIOLET}${BOLD}[*] Looking for latest backup to restore...${RESET}"

if [ ! -d "${BACKUP_ROOT}" ]; then
  echo -e "${YELLOW}No backups directory found at ${BACKUP_ROOT}.${RESET}"
  exit 1
fi

LATEST_BACKUP="$(ls -td "${BACKUP_ROOT}"/midnight-doll-* 2>/dev/null | head -n 1 || true)"

if [ -z "${LATEST_BACKUP}" ] || [ ! -d "${LATEST_BACKUP}" ]; then
  echo -e "${YELLOW}No previous backup directory found to restore.${RESET}"
  exit 1
fi

echo -e "${VIOLET}[*] Restoring from backup:${RESET} ${LATEST_BACKUP}"

# 1. Restore original theme name
ORIGINAL_THEME="default"
if [ -f "${LATEST_BACKUP}/original_theme.txt" ]; then
  ORIGINAL_THEME="$(cat "${LATEST_BACKUP}/original_theme.txt" | tr -d '[:space:]')"
fi
echo -e "    ✓ Detected original theme: ${ORIGINAL_THEME}"

# 2. Restore active theme directory if backed up
if [ -d "${LATEST_BACKUP}/active-theme" ]; then
  mkdir -p "${HOME}/.config/omarchy/themes"
  cp -r "${LATEST_BACKUP}/active-theme/"* "${HOME}/.config/omarchy/themes/${ORIGINAL_THEME}/" 2>/dev/null || true
  echo -e "    ✓ Restored active theme files for ${ORIGINAL_THEME}"
fi

# 3. Restore previous Midnight-Doll directory or remove if newly installed
if [ -d "${LATEST_BACKUP}/existing-midnight-doll" ]; then
  rm -rf "${HOME}/.config/omarchy/themes/midnight-doll"
  cp -r "${LATEST_BACKUP}/existing-midnight-doll/"* "${HOME}/.config/omarchy/themes/midnight-doll/" 2>/dev/null || true
  echo -e "    ✓ Restored previous Midnight-Doll theme configuration"
else
  rm -rf "${HOME}/.config/omarchy/themes/midnight-doll"
  echo -e "    ✓ Removed Midnight-Doll theme directory"
fi

# 4. Restore or clean configs
for cfg in "sys-hud.sh" "cava.conf" "midnight-shortcuts.json" "set-accent.sh"; do
  if [ -f "${LATEST_BACKUP}/${cfg}" ]; then
    cp "${LATEST_BACKUP}/${cfg}" "${HOME}/.config/omarchy/"
    echo -e "    ✓ Restored ~/.config/omarchy/${cfg}"
  else
    rm -f "${HOME}/.config/omarchy/${cfg}"
    echo -e "    ✓ Removed ~/.config/omarchy/${cfg}"
  fi
done

if [ -f "${LATEST_BACKUP}/shell.json" ]; then
  cp "${LATEST_BACKUP}/shell.json" "${HOME}/.config/omarchy/"
  echo -e "    ✓ Restored ~/.config/omarchy/shell.json"
fi

# 5. Clean up Midnight-Doll plugins and reset bar
if command -v omarchy &> /dev/null; then
  echo -e "${VIOLET}[*] Resetting bar and disabling Midnight-Doll plugins...${RESET}"
  omarchy bar reset >/dev/null 2>&1 || true
  omarchy plugin disable midnight-doll.workspaces >/dev/null 2>&1 || true
  omarchy plugin disable midnight-doll.menu >/dev/null 2>&1 || true
  omarchy plugin disable midnight-doll.clock >/dev/null 2>&1 || true
  omarchy plugin enable omarchy.menu >/dev/null 2>&1 || true
fi
rm -rf "${HOME}/.config/omarchy/plugins/midnight-doll."*

if [ -d "${LATEST_BACKUP}/existing-plugins" ]; then
  cp -r "${LATEST_BACKUP}/existing-plugins/"* "${HOME}/.config/omarchy/plugins/" 2>/dev/null || true
  echo -e "    ✓ Restored previous plugin configuration"
else
  echo -e "    ✓ Removed Midnight-Doll user plugins"
fi

# 6. Reactivate original theme
if command -v omarchy &> /dev/null && [ -n "${ORIGINAL_THEME}" ]; then
  echo -e "${PINK}[*] Reactivating original theme: ${ORIGINAL_THEME}...${RESET}"
  omarchy theme set "${ORIGINAL_THEME}" || true
  omarchy restart shell || true
fi

echo -e "\n${GREEN}${BOLD}✓ System successfully restored to pre-Midnight-Doll state (${ORIGINAL_THEME})!${RESET}\n"
