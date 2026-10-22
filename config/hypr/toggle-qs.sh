#!/bin/sh
# Abre/fecha um shell do quickshell:  toggle-qs.sh launcher | power
n="$1"
if pgrep -f -- "-c $n\$" >/dev/null 2>&1; then
    pkill -f -- "-c $n\$"
else
    exec qs -c "$n"
fi
