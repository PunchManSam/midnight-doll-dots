#!/usr/bin/env bash
# omarchy:summary=Launch an audio equalizer if installed or audio settings if not
# Part of Midnight-Doll Cyberdeck dots

# Set terminal window title (if launched in terminal)
printf "\033]0;%s\007" "Midnight Doll // Audio Control" 2>/dev/null || true

# 1. Equalizer Detection & Launch
# Priority cascade: easyeffects -> jamesdsp -> pulseaudio-equalizer-gtk -> qpaeq -> flatpaks
if command -v easyeffects &>/dev/null; then
  if command -v omarchy-launch-or-focus &>/dev/null; then
    exec omarchy-launch-or-focus easyeffects easyeffects
  else
    exec easyeffects "$@"
  fi
elif command -v jamesdsp &>/dev/null; then
  if command -v omarchy-launch-or-focus &>/dev/null; then
    exec omarchy-launch-or-focus jamesdsp jamesdsp
  else
    exec jamesdsp "$@"
  fi
elif command -v pulseaudio-equalizer-gtk &>/dev/null; then
  if command -v omarchy-launch-or-focus &>/dev/null; then
    exec omarchy-launch-or-focus pulseaudio-equalizer-gtk pulseaudio-equalizer-gtk
  else
    exec pulseaudio-equalizer-gtk "$@"
  fi
elif command -v qpaeq &>/dev/null; then
  if command -v omarchy-launch-or-focus &>/dev/null; then
    exec omarchy-launch-or-focus qpaeq qpaeq
  else
    exec qpaeq "$@"
  fi
elif command -v flatpak &>/dev/null && flatpak info com.github.wwmm.easyeffects &>/dev/null; then
  exec flatpak run com.github.wwmm.easyeffects "$@"
elif command -v flatpak &>/dev/null && flatpak info me.timschneeberger.jdsp4linux &>/dev/null; then
  exec flatpak run me.timschneeberger.jdsp4linux "$@"

# 2. Audio Settings Fallback (when no equalizer is installed)
# Priority cascade: pavucontrol -> pavucontrol-qt -> pwvucontrol -> omarchy-shell audio panel -> alsamixer
elif command -v pavucontrol &>/dev/null; then
  if command -v omarchy-launch-or-focus &>/dev/null; then
    exec omarchy-launch-or-focus pavucontrol pavucontrol
  else
    exec pavucontrol "$@"
  fi
elif command -v pavucontrol-qt &>/dev/null; then
  if command -v omarchy-launch-or-focus &>/dev/null; then
    exec omarchy-launch-or-focus pavucontrol-qt pavucontrol-qt
  else
    exec pavucontrol-qt "$@"
  fi
elif command -v pwvucontrol &>/dev/null; then
  if command -v omarchy-launch-or-focus &>/dev/null; then
    exec omarchy-launch-or-focus pwvucontrol pwvucontrol
  else
    exec pwvucontrol "$@"
  fi
elif command -v omarchy-shell &>/dev/null; then
  exec omarchy-shell shell toggle omarchy.audio
elif command -v alsamixer &>/dev/null; then
  if command -v omarchy-launch-or-focus-tui &>/dev/null; then
    exec omarchy-launch-or-focus-tui alsamixer
  else
    exec alsamixer "$@"
  fi
else
  notify-send "Audio Control" "No equalizer or audio control application found." -i audio-volume-high 2>/dev/null || true
fi
