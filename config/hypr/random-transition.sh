#!/usr/bin/env bash
IMG="$1"
P3_CHANCE=15   # % de chance de usar a animação do Persona 3

if (( RANDOM % 100 < P3_CHANCE )); then
    cols=$("$HOME/.config/hypr/wallcolors.py" "$IMG" --no-reload 2>/dev/null)
    c1=$(sed -n 's/.*primary=\(#[0-9a-f]*\).*/\1/p' <<<"$cols")
    c2=$(sed -n 's/.*secondary=\(#[0-9a-f]*\).*/\1/p' <<<"$cols")
    if qs -c p3 ipc call p3 playColors "${c1:-#1f6bff}" "${c2:-#0a2fd8}" 2>/dev/null; then
        sleep 0.7
        awww img "$IMG" --transition-type none
        exit 0
    fi
fi
awww img "$IMG" --transition-type random --transition-duration 1 --transition-fps 60
