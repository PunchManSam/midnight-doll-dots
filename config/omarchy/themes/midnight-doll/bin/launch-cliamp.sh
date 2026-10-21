#!/usr/bin/env bash
# omarchy:summary=Launch CLIAMP retro terminal music player in a new terminal session
# Part of Midnight-Doll Cyberdeck dots

# Set terminal window title (if launched in terminal)
printf "\033]0;%s\007" "CLIAMP" 2>/dev/null || true

# Always launch a fresh terminal session running cliamp
if command -v omarchy-launch-tui &>/dev/null; then
  exec omarchy-launch-tui --app-id=TUI.cliamp cliamp "$@"
elif command -v uwsm-app &>/dev/null && command -v xdg-terminal-exec &>/dev/null; then
  exec setsid uwsm-app -- xdg-terminal-exec --app-id=TUI.cliamp cliamp "$@"
elif command -v xdg-terminal-exec &>/dev/null; then
  exec setsid xdg-terminal-exec cliamp "$@"
elif command -v ghostty &>/dev/null; then
  exec ghostty -e cliamp "$@"
elif command -v kitty &>/dev/null; then
  exec kitty -e cliamp "$@"
elif command -v konsole &>/dev/null; then
  exec konsole -e cliamp "$@"
elif command -v alacritty &>/dev/null; then
  exec alacritty -e cliamp "$@"
elif command -v foot &>/dev/null; then
  exec foot -e cliamp "$@"
else
  exec cliamp "$@"
fi
