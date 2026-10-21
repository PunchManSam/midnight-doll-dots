#!/usr/bin/env bash
# omarchy:summary=Launch or focus CLIAMP retro terminal music player
# Part of Midnight-Doll Cyberdeck dots

if command -v omarchy-launch-or-focus-tui &>/dev/null; then
  exec omarchy-launch-or-focus-tui cliamp
elif command -v gtk-launch &>/dev/null && [ -f /usr/share/applications/cliamp.desktop ]; then
  exec gtk-launch cliamp.desktop
elif command -v xdg-terminal-exec &>/dev/null; then
  exec xdg-terminal-exec cliamp
elif command -v ghostty &>/dev/null; then
  exec ghostty -e cliamp
elif command -v kitty &>/dev/null; then
  exec kitty -e cliamp
elif command -v alacritty &>/dev/null; then
  exec alacritty -e cliamp
elif command -v foot &>/dev/null; then
  exec foot -e cliamp
else
  exec cliamp "$@"
fi
