#!/bin/bash
# omarchy:summary=Launch communicating applications & socket inspector with smart fallback

if command -v bandwhich &>/dev/null; then
  exec bandwhich "$@"
elif command -v nethogs &>/dev/null; then
  exec nethogs "$@"
elif command -v sniffnet &>/dev/null; then
  exec sniffnet "$@"
elif command -v iftop &>/dev/null; then
  exec iftop "$@"
elif command -v bmon &>/dev/null; then
  exec bmon "$@"
elif command -v termshark &>/dev/null; then
  exec termshark "$@"
else
  # Native zero-dependency fallback using ss
  clear
  tput civis 2>/dev/null
  trap 'tput cnorm 2>/dev/null; clear; exit 0' INT TERM EXIT
  while true; do
    tput cup 0 0 2>/dev/null
    echo -e "\033[1;35m💀 MIDNIGHT-DOLL // COMMUNICATING APPLICATIONS & SOCKETS\033[0m"
    echo -e "\033[0;90mTip: Install 'bandwhich' or 'nethogs' via pacman for interactive per-process bandwidth.\033[0m"
    echo -e "\033[0;35m────────────────────────────────────────────────────────────────────────────────────────\033[0m"
    max_lines=$(( $(tput lines 2>/dev/null || echo 30) - 5 ))
    ss -tup | head -n "$max_lines"
    tput ed 2>/dev/null
    echo -e "\n\033[0;90m[Press 'q' to close]\033[0m"
    if [ -t 0 ]; then
      read -t 1.5 -n 1 key && [[ "$key" =~ ^[qQ]$ ]] && break
    else
      sleep 1.5
    fi
  done
fi
