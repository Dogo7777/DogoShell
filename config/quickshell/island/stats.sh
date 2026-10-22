#!/usr/bin/env bash
# Imprime uma linha a cada 2s:  cpu% mem% tempC disco% interface
prev_t=0
prev_i=0

tfile=""
for h in /sys/class/hwmon/hwmon*; do
    case "$(cat "$h/name" 2>/dev/null)" in
        k10temp|coretemp|zenpower) tfile="$h/temp1_input"; break ;;
    esac
done
[ -z "$tfile" ] && tfile=/sys/class/thermal/thermal_zone0/temp

while true; do
    read -r _ u n s i w q sq st _ < /proc/stat
    t=$((u + n + s + i + w + q + sq + st))
    idle=$((i + w))
    dt=$((t - prev_t))
    di=$((idle - prev_i))
    if [ "$dt" -gt 0 ]; then cpu=$(( 100 * (dt - di) / dt )); else cpu=0; fi
    prev_t=$t
    prev_i=$idle

    mem=$(awk '/MemTotal/{t=$2} /MemAvailable/{a=$2} END{printf "%d", (t-a)*100/t}' /proc/meminfo)
    temp=$(( $(cat "$tfile" 2>/dev/null || echo 0) / 1000 ))
    disk=$(df --output=pcent / | tail -1 | tr -dc '0-9')
    iface=$(ip -o route get 1.1.1.1 2>/dev/null | awk '{for (k=1;k<=NF;k++) if ($k=="dev") print $(k+1)}')

    printf '%s %s %s %s %s\n' "$cpu" "$mem" "$temp" "$disk" "${iface:-offline}"
    sleep 2
done
