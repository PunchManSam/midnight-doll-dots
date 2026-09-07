#!/bin/bash
state_file="${XDG_RUNTIME_DIR:-/tmp}/omarchy_syshud_${UID:-$USER}.state"
read -r cpu u n s i io ir st g gn < /proc/stat
total=$((u + n + s + i + io + ir + st))
idle=$i
rx=$(awk 'NR>2 && $1 !~ /^lo:/ {rx+=$2} END {print rx}' /proc/net/dev)
tx=$(awk 'NR>2 && $1 !~ /^lo:/ {tx+=$10} END {print tx}' /proc/net/dev)
now=$(date +%s%N)

cpu_pct=0
rx_rate=0
tx_rate=0

if [ -f "$state_file" ]; then
  read -r p_total p_idle p_rx p_tx p_now < "$state_file"
  d_total=$((total - p_total))
  d_idle=$((idle - p_idle))
  d_time=$(( (now - p_now) / 1000000 )) # ms
  if [ "$d_total" -gt 0 ]; then
    cpu_pct=$(( (d_total - d_idle) * 100 / d_total ))
  fi
  if [ "$d_time" -gt 0 ]; then
    rx_rate=$(( (rx - p_rx) * 1000 / d_time )) # B/s
    tx_rate=$(( (tx - p_tx) * 1000 / d_time )) # B/s
  fi
fi

echo "$total $idle $rx $tx $now" > "$state_file"

# Format net rate
fmt_rate() {
  local b=$1
  if [ "$b" -ge 1048576 ]; then
    awk "BEGIN {printf \"%.1fM\", $b/1048576}"
  elif [ "$b" -ge 1024 ]; then
    awk "BEGIN {printf \"%dK\", $b/1024}"
  else
    echo "${b}B"
  fi
}

rx_fmt=$(fmt_rate $rx_rate)
tx_fmt=$(fmt_rate $tx_rate)

mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
mem_avail=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
mem_used=$((mem_total - mem_avail))
mem_pct=$((mem_used * 100 / mem_total))
mem_gb=$(awk "BEGIN {printf \"%.1fG\", $mem_used/1048576}")

disk_pct=$(df -P / | awk 'NR==2 {gsub("%","",$5); print $5}')

echo "CPU:$cpu_pct;MEM:$mem_pct;MEM_GB:$mem_gb;DSK:$disk_pct;RX:$rx_fmt;TX:$tx_fmt"
