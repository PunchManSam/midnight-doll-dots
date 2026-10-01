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

# CPU Temperature
cpu_temp=0
temp_sensor="${XDG_RUNTIME_DIR:-/tmp}/omarchy_syshud_temp_${UID:-$USER}.sensor"
if [ -f "$temp_sensor" ]; then
  read -r sensor_path < "$temp_sensor"
  if [ -r "$sensor_path" ]; then
    raw_temp=$(cat "$sensor_path" 2>/dev/null)
    if [ -n "$raw_temp" ] && [ "$raw_temp" -gt 0 ] 2>/dev/null; then
      cpu_temp=$(( (raw_temp + 500) / 1000 ))
    fi
  fi
fi

if [ "$cpu_temp" -eq 0 ]; then
  # Discover CPU temperature sensor in /sys/class/hwmon
  for h in /sys/class/hwmon/hwmon*; do
    [ -d "$h" ] || continue
    name=$(cat "$h/name" 2>/dev/null)
    case "$name" in
      coretemp|k10temp|zenpower|cpu_thermal|soc_thermal)
        for t in "$h"/temp*_input; do
          [ -f "$t" ] || continue
          val=$(cat "$t" 2>/dev/null)
          if [ -n "$val" ] && [ "$val" -gt 0 ] 2>/dev/null; then
            cpu_temp=$(( (val + 500) / 1000 ))
            echo "$t" > "$temp_sensor"
            break 2
          fi
        done
        ;;
    esac
  done
fi

if [ "$cpu_temp" -eq 0 ]; then
  # Fallback to thermal zones
  for tz in /sys/class/thermal/thermal_zone*; do
    [ -d "$tz" ] || continue
    type=$(cat "$tz/type" 2>/dev/null)
    case "$type" in
      *pkg_temp*|*cpu*|*soc*|acpitz*)
        val=$(cat "$tz/temp" 2>/dev/null)
        if [ -n "$val" ] && [ "$val" -gt 0 ] 2>/dev/null; then
          cpu_temp=$(( (val + 500) / 1000 ))
          echo "$tz/temp" > "$temp_sensor"
          break
        fi
        ;;
    esac
  done
fi

if [ "$cpu_temp" -eq 0 ] && command -v sensors &>/dev/null; then
  val=$(sensors 2>/dev/null | awk '/Package id 0|Tctl|CPU Temperature|Core 0/ {print $0; exit}' | grep -oE '[0-9]+(\.[0-9]+)?°C' | head -1 | tr -d '°C' | cut -d. -f1)
  if [ -n "$val" ] && [ "$val" -gt 0 ] 2>/dev/null; then
    cpu_temp=$val
  fi
fi

# Fan Speed / RPM (supports single and multi-fan systems)
fan_rpms=()
fan_pcts=()

for h in /sys/class/hwmon/hwmon*; do
  [ -d "$h" ] || continue
  for f in "$h"/fan*_input; do
    [ -f "$f" ] || continue
    val=$(cat "$f" 2>/dev/null)
    if [ -n "$val" ] && [ "$val" -gt 0 ] 2>/dev/null; then
      max_file="${f%_input}_max"
      max_fan=4500
      if [ -f "$max_file" ]; then
        m_val=$(cat "$max_file" 2>/dev/null)
        [ -n "$m_val" ] && [ "$m_val" -gt 0 ] 2>/dev/null && max_fan=$m_val
      fi
      pct=$(( val * 100 / max_fan ))
      [ "$pct" -gt 100 ] && pct=100
      fan_rpms+=("$val")
      fan_pcts+=("$pct")
    fi
  done
done

if [ "${#fan_rpms[@]}" -eq 0 ] && [ -r /proc/acpi/ibm/fan ]; then
  val=$(awk '/speed:/ {print $2}' /proc/acpi/ibm/fan 2>/dev/null)
  if [ -n "$val" ] && [ "$val" -gt 0 ] 2>/dev/null; then
    pct=$(( val * 100 / 4500 ))
    [ "$pct" -gt 100 ] && pct=100
    fan_rpms+=("$val")
    fan_pcts+=("$pct")
  fi
fi

if [ "${#fan_rpms[@]}" -eq 0 ] && command -v sensors &>/dev/null; then
  while read -r line; do
    val=$(echo "$line" | awk '{print $2}' | tr -d 'RPM' | tr -d ' ')
    if [ -n "$val" ] && [ "$val" -gt 0 ] 2>/dev/null; then
      pct=$(( val * 100 / 4500 ))
      [ "$pct" -gt 100 ] && pct=100
      fan_rpms+=("$val")
      fan_pcts+=("$pct")
    fi
  done < <(sensors 2>/dev/null | grep -iE 'fan[0-9]*:')
fi

if [ "${#fan_rpms[@]}" -eq 0 ]; then
  if [ "$cpu_temp" -ge 85 ]; then
    f_pct=100; f_rpm=4800
  elif [ "$cpu_temp" -ge 75 ]; then
    f_pct=$(( 70 + (cpu_temp - 75) * 3 ))
    f_rpm=$(( 3400 + (cpu_temp - 75) * 140 ))
  elif [ "$cpu_temp" -ge 60 ]; then
    f_pct=$(( 40 + (cpu_temp - 60) * 2 ))
    f_rpm=$(( 2000 + (cpu_temp - 60) * 90 ))
  elif [ "$cpu_temp" -ge 45 ]; then
    f_pct=$(( 15 + (cpu_temp - 45) * 1 ))
    f_rpm=$(( 1000 + (cpu_temp - 45) * 60 ))
  else
    f_pct=0; f_rpm=0
  fi
  fan_rpms+=("$f_rpm")
  fan_pcts+=("$f_pct")
fi

fan_rpm_str=$(IFS=,; echo "${fan_rpms[*]}")
fan_pct_str=$(IFS=,; echo "${fan_pcts[*]}")
primary_fan_rpm=${fan_rpms[0]:-0}
primary_fan_pct=${fan_pcts[0]:-0}
for r in "${fan_rpms[@]}"; do
  [ "$r" -gt "$primary_fan_rpm" ] && primary_fan_rpm=$r
done
for p in "${fan_pcts[@]}"; do
  [ "$p" -gt "$primary_fan_pct" ] && primary_fan_pct=$p
done

disk_pct=$(df -P / | awk 'NR==2 {gsub("%","",$5); print $5}')

echo "CPUTEMP:$cpu_temp;CPU:$cpu_pct;FAN:$primary_fan_rpm;FAN_PCT:$primary_fan_pct;FANS:$fan_rpm_str;FAN_PCTS:$fan_pct_str;MEM:$mem_pct;MEM_GB:$mem_gb;DSK:$disk_pct;RX:$rx_fmt;TX:$tx_fmt"
